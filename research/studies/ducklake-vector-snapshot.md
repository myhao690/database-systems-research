> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# C13 snapshot-index lifecycle feasibility gate

**Date:** 2026-10-27. **Verdict:** A low-intrusion, snapshot-pinned **external prototype works** for controlled DuckLake UPDATE/DELETE/INSERT and file rewrite, but the mechanism tested is *known base-index + delta prior art*, not yet an independent MSc thesis contribution. PDX's own incremental mutation is a strong, cheap baseline. The pinned DuckLake executable has a compaction change-feed bug that [upstream PR #1839](https://github.com/duckdb/ducklake/pull/1839) fixed on 2026-10-27; it must not be presented as our discovery or a proposed novel fix. **Do not begin a C++ storage/index patch yet.**

## Isolation and reproducible state transitions

Cloned the original SIFT1M/40-Parquet-file catalog into `snapshot_sift`; all writes were confined to this sibling directory, not C17 or the original C13 catalog. Attached with `OVERRIDE_DATA_PATH true` (required because the catalog stores its original data path). Python DuckDB 2.0.0, DuckLake extension `417a9117f5`, PDX `f6a26df...`.

| Snapshot | Operation | Measured outcome |
|---:|---|---|
| S41 | immutable million-vector base | existing 518 MB PDX IVF index; `rowid==id` verified for this original append-only table only |
| S42 | update 1,000 evenly spaced existing embeddings by +0.1 | 0.132 s SQL; change feed reports 1,000 pre/post pairs |
| S43 | move prior q0 nearest far away; move a distant vector exactly to q0 | 0.012 s SQL; q0 exact nearest changes from ID 932085 to 999999 while old rowid remains visible with changed vector |
| S44 | delete q1 old nearest | 0.011 s SQL |
| S45 | insert vector exactly at q1 | 0.007 s SQL; stored `id=1000000`, **logical `rowid=1001000`**—explicit mapping is mandatory |
| S46 | forced deletion-aware rewrite with `delete_threshold=>0.0` | 0.688 s; rewrites 40 data files to 1, active files 41→2; sampled current rowids unchanged, old S41 time travel remains readable |

S41–S45 form controlled, **synthetic update patterns on real SIFT vectors**, not a realistic workload trace. The test covers one metric, one index type, a local warm catalog and one table. It does not establish all-snapshot correctness, concurrent transaction atomicity, crash safety, NULL semantics, filtered search, historical sidecar garbage collection, or remote I/O.

## Existing mechanisms before ours

PDX Python/C++ binding already exposes [`append`, `delete`, `save`, `filtered_search`](https://github.com/cwida/PDX/blob/f6a26df53c143dbe64b1e6c1ba22d8f1de931f7b/python/lib.cpp#L35-L52). A loaded base index plus 1,002 in-memory `delete`/`append` operations took **0.045 s** and correctly moved q0's top candidate to ID 999999. Saving the whole mutated index took **0.608 s** and produced another 518 MB file. A full PDX rebuild took **1.242 s**, plus **0.612 s** to save. Thus comparing only to rebuild would exaggerate our contribution.

Our *external* prototype freezes S41's PDX index, uses S42/S43 `table_changes` to mark stale rowids, retrieves 1,002 up-to-date vectors from DuckLake's snapshot reader, searches the unchanged base with adaptive over-fetch/refill, exact-scores the small live delta, merges distances, and fetches final records via `rowid IN` at the selected snapshot. The S43 delta sidecar is **0.522 MB**, change-feed query **0.036 s**, delta vector retrieval **0.156 s** (one run each). This is a **feasibility lower-fidelity prototype**, not a safe publication protocol or a single SQL operator. Repeating this generic base+delta pattern is not novel: [Lance already covers indexed and unindexed/stale fragments](https://github.com/lance-format/lance/blob/2ed8e2db83a7edf93048280f7a33d1684e7a9027/rust/lance/src/dataset/scanner.rs#L4675-L4730).

## End-to-end competing controls after S43 (same data, snapshot, nprobe=128)

8 independent SIFT queries × 12 shuffled repeats per mode, fully fetching ten `id,payload` rows. `payload='record-N'` remains synthetic. p50/p95 milliseconds; R@10 is against exact DuckLake SQL truth. All modes use the same persisted S43 DuckLake table. `native mutation` means PDX delete/append then full save, *not* DuckLake-native index integration.

| S43 index path | R@10 mean | search p50/p95 | record fetch p50/p95 | full p50/p95 | persisted incremental bytes |
|---|---:|---:|---:|---:|---:|
| S41 base + exact S43 delta | .975 | 0.856 / 1.724 | 6.798 / 8.584 | **7.654 / 9.943** | 0.522 MB delta |
| PDX native delete+append | .975 | 0.497 / 0.628 | 6.777 / 8.983 | **7.238 / 9.510** | 518 MB full index |
| full PDX rebuild | .988 | 0.483 / 0.636 | 6.748 / 8.142 | **7.221 / 8.590** | 518 MB full index |

The overlay retains historical S41 without another base index and writes ~1,000× fewer new bytes per snapshot, but **loses query time**: ~0.42 ms p50 relative to native mutation, with an over-fetch refill on q0. It is not a universally faster query mechanism. In this one trace, approximate *mean-total-time* break-even against native mutation is `(0.045+0.608−0.036−0.156)s / (8.219−7.578)ms ≈ 720 queries per snapshot`, ignoring sidecar publication/load/GC and using one-off maintenance timings. This is a **model inference**, not a measured production threshold. Preserving multiple snapshots could justify delta storage; a latest-only workload favors native PDX mutation. Full rebuild differs in recall, so it is contextual rather than strictly equal quality.

## INSERT, DELETE and real rewrite: a version-gating surprise

At S45, `rowid=1001000` differs from stored ID 1000000. The base S41 index positions can map to original rowids, but new rows must use an explicit ID map. Forced rewrite to S46 moves physical file locations while preserving sampled logical rowids and S41 time travel. That supports *semantic* PDX reuse across file rewrite, but **invalidates physical locators**; no file-aware locator was implemented.

The pinned extension's `table_changes('vectors',46,46)` reported **998,997 `update_preimage` + 998,997 `update_postimage`** rows for S46's physically rewritten but logically unchanged survivors. A naive change-feed overlay would attempt to reindex nearly the entire million-vector table and break its cost model. This is a **version-specific upstream-known bug**, not a new optimization idea: [upstream PR #1839](https://github.com/duckdb/ducklake/pull/1839), incorporating the [documented fix](https://github.com/PeterVanHolland/ducklake/pull/145), was merged on 2026-10-27. We did not run the newly merged executable. To test the remaining semantics with the pinned executable, `overlay_compaction_probe.py` intentionally excludes the known rewrite snapshot from the feed (events S42–S45 only), then reads S46 data through DuckLake: q1 exact and overlay top both become newly inserted rowid 1001000, mean R@10 .975, full p50/p95 **10.466/12.266 ms** over 48 runs. That skip is only a diagnostic workaround, **not** our proposed fix or a crash-safe design. S46's 2 active files had a **higher observed** small-payload hydration median than S43's 41, but these runs were not a paired performance comparison; file count alone is an invalid predictor.

## Decision

- **Can something be implemented? Yes:** an external snapshot-aware base+delta PDX/DuckLake prototype already returns correct checked results across controlled updates, delete, insert and forced rewrite (with the pinned-version feed workaround).
- **Is the tested mechanism itself sufficient for the user's excellent MSc target? No:** PDX already handles incremental mutation, Lance already has base+delta coverage, and DuckLake's rewrite-feed issue is already fixed upstream. This prototype is an integration/control, not a defensible original core contribution.
- **What remains worth one bounded search?** A *DuckLake-specific* end-to-end bottleneck after the best native-mutation/snapshot baseline: realistic payload/filter/update traces, latest+historical queries, cold/remote storage, and actual index/sidecar publication, retention and cleanup costs. A candidate mechanism must improve a multi-snapshot **total-cost frontier** (query latency, update cost, index bytes, correct snapshot results) over full per-snapshot PDX save and Lance at matched semantics—not just beat full rebuild or exact scan. If it cannot, C13 as an outstanding systems thesis is No-Go; it can still be a solid integration/evaluation project.

## Reproduction and files

Run in a **fresh isolated directory**, starting with a copy of the original SIFT catalog; scripts assert exact expected snapshot progression and output absence. Do not rerun mutating scripts against the archived `snapshot_sift`—it is now at S46. PDX index files and raw reports are archived under `overlay_sift/`, `overlay_query_compare/`, `overlay_compaction_skip_rewrite/`; the failed naive S46 feed run is retained in `overlay_compaction_probe.log` and reproducible through `overlay_compaction_unfixed_probe.py`.

```bash
SRC=<local-projects>/ducklake_vector_snapshot_gate_20261027
RUN=$(mktemp -d /tmp/c13-lifecycle-replay.XXXXXX)
cp "$SRC"/{update_probe.py,overlay_gate.py,overlay_query_compare.py,lifecycle_probe.py,compaction_force_probe.py,overlay_compaction_probe.py,overlay_compaction_unfixed_probe.py} "$RUN"/
ln -s "$SRC/pdx_sift" "$RUN/pdx_sift"
cp -a /tmp/c13-vector-probe-list/sift "$RUN/snapshot_sift"
cd "$RUN"
V=/tmp/vector-pdx-venv-20261027/bin/python
$V update_probe.py
$V overlay_gate.py
$V overlay_query_compare.py
$V lifecycle_probe.py
$V compaction_force_probe.py
$V overlay_compaction_unfixed_probe.py  # expected assertion on pinned old extension
$V overlay_compaction_probe.py          # diagnostic skip of known rewrite snapshot
```

`update_sift_report.json`, `lifecycle_probe.json`, `compaction_force_report.json`, per-mode JSON and scripts preserve actual results. Nothing here is a full DuckLake extension, upstream PR or novel ANN algorithm.
