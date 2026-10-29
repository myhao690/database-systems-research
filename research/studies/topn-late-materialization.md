> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# Final design gate: Top-N late-materialization admission

**Verdict (2026-10-25): No-Go for a threshold/admission C++ patch; retain the performance gap as a documented research observation.** This is not a claim that a good optimizer rule is impossible. It says the currently available cheap metadata does not justify one, and the missing physical-cost signal would widen the implementation well beyond a minimal upstream change. No DuckDB source was modified.

## Claim tested

Can the existing optimizer decide when to use native-table Top-N late materialization from **cheap, already maintained per-column metadata**, without sampling data or traversing every storage segment?

The answer on the inspected `main` commit `1641475ef1db08ec063631ff6a8f08d9d6736ae7` is **not yet**:

1. [`StringStats`](https://github.com/duckdb/duckdb/blob/1641475ef1db08ec063631ff6a8f08d9d6736ae7/src/include/duckdb/storage/statistics/string_stats.hpp#L43-L55) gives max and total **logical** string bytes. Native table scan's [`statistics_extended`](https://github.com/duckdb/duckdb/blob/1641475ef1db08ec063631ff6a8f08d9d6736ae7/src/function/table/table_scan.cpp#L1050-L1064) can fetch cached column stats before the later statistics-propagation pass. That is a plausible O(projected columns) input, not a scan-cost estimate.
2. Existing row-group [`get_partition_stats`](https://github.com/duckdb/duckdb/blob/1641475ef1db08ec063631ff6a8f08d9d6736ae7/src/function/table/table_scan.cpp#L1087-L1091) still supplies logical stats, with row-group traversal; it does not add compressed byte or overflow counts.
3. Segment metadata has compression and optional physical byte fields in [`ColumnSegment`](https://github.com/duckdb/duckdb/blob/1641475ef1db08ec063631ff6a8f08d9d6736ae7/src/include/duckdb/storage/table/column_segment.hpp#L120-L133) / [`DataPointer`](https://github.com/duckdb/duckdb/blob/1641475ef1db08ec063631ff6a8f08d9d6736ae7/src/storage/table/column_segment.cpp#L300-L314), but the existing [`GetColumnSegmentInfo`](https://github.com/duckdb/duckdb/blob/1641475ef1db08ec063631ff6a8f08d9d6736ae7/src/storage/table/row_group_collection.cpp#L2256-L2287) and [`column_data.cpp`](https://github.com/duckdb/duckdb/blob/1641475ef1db08ec063631ff6a8f08d9d6736ae7/src/storage/table/column_data.cpp#L1375-L1444) paths enumerate segments and may load metadata. No already-cached O(columns) physical-size/compression/overflow summary was found. Inspecting per-segment data does **not inherently require** a storage-format change, but using it in every query plan would add size-dependent planning work.
4. [`StringAnalyzeState`](https://github.com/duckdb/duckdb/blob/1641475ef1db08ec063631ff6a8f08d9d6736ae7/src/storage/compression/string_uncompressed.cpp#L67-L102) counts overflow strings while analyzing compression, but this is transient, not a maintained optimizer statistic. Adding a persistent summary would need correct checkpoint, append/update, transaction, merge, serialization and unknown-stat semantics. Whether that is worth doing is a separate larger project.

## Empirical falsification of simple logical-width gates

| Case | Native-table payload facts | LIMIT 51, LM off→on | Physical layout observation |
|---|---|---|---|
| Issue-derived **medium** negative | Two strings total ~1.90 **GB logical bytes**, 485,168 rows; max string 2048 bytes | 2.40→2.79 ms (**regression**) | 5 `DICT_FSST` VARCHAR segments per column |
| Authentic Simple English Wikipedia positive | `text` total **269 MB logical bytes**, 241,787 rows; 8,966 (3.7%) values >=4096 bytes | 44.69→5.86 ms (**7.63×**) | 653 `Uncompressed` VARCHAR segments |
| Authentic English Wikipedia full first shard positive | `text` total **703 MB logical bytes**, 156,289 rows; 48,837 (31.2%) values >=4096 bytes | 405.52→42.92 ms (**9.45×**) | 2 `ZSTD` VARCHAR segments |

These are observations, **not proof that a given codec caused the gain**. They do prove that a rule monotonic in logical total bytes or mean width would rank the medium negative higher than the Simple English positive. A `max >= overflow threshold` gate happens to separate these particular cells, but [Issue #24935's prior analysis](https://github.com/duckdb/duckdb/issues/24935) already demonstrates false positives when only a minority of rows is long. `max`, mean and total do not encode long-value fraction, filter-conditioned width, Top-K winner correlation, compressed-byte cost or rowid locality. Even the *same* per-column summaries can correspond to opposite Top-K winner distributions. Current results also do not isolate cold-cache I/O, decoder CPU, or exact bytes read.

The English and Simple English data share one publisher and import pipeline, so they are robustness checks across distributions/codecs, **not three independent production systems**. The DuckDB issue attachment resembles confidential data but is not the original production table. A wider upstream performance claim would need further independent sources.

## Hard stop / future reopening condition

- **Stop now:** no default-threshold bump, `max>=4096` rule, or patch that calls `storage_info`/enumerates all segments during optimization. The current 5001 tests only show that both settings take the same full-sort plan; they do not benchmark a hypothetical new Top-N+LM implementation.
- **Reopen only if** a bounded O(projected columns) physical scan-cost signal is already available or can be maintained with a small, reviewable, transaction-safe change; then freeze a rule *before* evaluation, test filter/offset/reordering and prior issue counterexamples, and require independent-source held-out gains without material short-query regression. Both Top-N and LM gates must be handled coherently.
- If reopening requires pervasive storage-statistics persistence plus a large optimizer cost model, **No-Go as a master's core/upstream small PR**; do not hide the complexity by adding more hand-tuned modes or thresholds.

This gate is consistent with the user's thesis criterion: the **problem is real**, but the currently identified implementation is not yet a clean, broadly applicable contribution. The next candidate must be separately audited against current DuckDB source/upstream work before any patch.
