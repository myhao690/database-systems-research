> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# C13 SQL-cost and low-intrusion baseline gate

**Date:** 2026-10-27. **Decision:** For these two *warm, local, append-only* tables, **NO-GO for claiming that File-Aware Materialization saves substantial work merely by pruning the 40-file list**. A broader snapshot-aware retrieval thesis remains **CONDITIONAL**, pending genuine payload/remote/update evidence. No storage/index patch was made.

## Question and controlled setup

Test the proposed sequence: (1) identify removable parts of the existing ~5–6 ms PDX→DuckLake path, (2) use existing SQL/Python interfaces to find a low-intrusion control, (3) only pursue a new file-aware mechanism if meaningful residual *file-access* work is established.

Use the existing SIFT1M 128D/L2 and GloVe 1.18M 100D/cosine DuckLake tables (40 Parquet files each) at snapshot 41, PDX saved IVF index at nprobe=128, 8 distinct queries × 6 repeats, shuffled SQL-method order, DuckDB Python 2.0.0 + DuckLake extension `417a9117f5`, 4 threads, local warm cache. SIFT/GloVe vectors are real, but `payload='record-N'` is artificial and tiny. Exact `rowid == id` was verified on these original append-only tables, **not** a general DuckLake invariant. Every result row set was checked against the same ten PDX hits. Full times below include PDX search and SQL fetch, or PDX-in-SQL UDF and fetch; they exclude identical cheap client ranking reconstruction. One Python connection and attached catalog were reused. No network/S3, crash or concurrent update test.

## Timed results (48 measurements per method)

All values in ms, p50/p95. `single SQL UDF` invokes the *same loaded PDX index exactly once* through a Python scalar UDF in a DuckDB SQL statement. It is a best-effort one-client-SQL-call control, **not** native C++ integration. `id` is the stored ascending column and is safe here only because the tested snapshot has the verified mapping.

| Dataset | PDX R@10 | external PDX + `rowid IN` | parameterized `rowid IN` | external PDX + `id IN` | single-SQL PDX UDF + `rowid IN` | SQL-only `SELECT ?` / zero-result DuckLake query |
|---|---:|---:|---:|---:|---:|---:|
| SIFT1M | 0.975 | 5.537 / 6.833 | 5.521 / 7.409 | 5.883 / 7.437 | 5.560 / 7.732 | 0.195 / 0.337 ; 1.374 / 1.995 |
| GloVe | 0.925 | 6.343 / 7.389 | 6.381 / 7.606 | 6.672 / 7.730 | 6.072 / 7.235 | 0.203 / 0.259 ; 1.397 / 1.679 |

The single-SQL UDF changes SIFT p50 by **+0.023 ms** (worse) and GloVe p50 by **−0.271 ms** (about 4% better); it does not eliminate most of the ~5–6 ms path. Parameterization and substituting the stored `id` are not wins here. Omitting `payload` improves SQL p50 only from 5.061→4.385 ms (SIFT) or 5.672→4.751 ms (GloVe), but is **not an equivalent query**. `SELECT ?` establishes that Python→DuckDB call overhead itself is far smaller than the fetch; zero-result DuckLake planning/binding is already ~1.4 ms, but cannot simply be subtracted as a causal component. A separate 8-query × 5-repeat `PREPARE/EXECUTE` control was slower: SIFT SQL p50 **8.408 vs 4.957 ms** and GloVe **10.465 vs 5.948 ms** (prepared vs literal). Its plans are archived; no prepared-query gain was found.

## Actual work vs the misleading 40-file plan count

Separately profiled the *same eight PDX hit sets* twice, with `rowid IN (...)` and `id IN (...)`, after timing. Profile counters are **DuckDB-reported logical read bytes**, not physical cold-disk/remote requests. Profiling overhead means these profile timings are not the timed results above.

| Dataset / projection | `rowid` files listed | `id` files listed | scan output rows (both, median) | logical bytes read (rowid / id, median) | paired mean byte difference |
|---|---:|---:|---:|---:|---:|
| SIFT `id,payload` | 40 | 4–9 | 187,500 | 1.697 / 1.681 MB | id 1.05% less |
| GloVe `id,payload` | 40 | 7–10 | 281,083 | 2.529 / 2.514 MB | id 0.64% less |
| SIFT `id,embedding` | 40 | 4–9 | 187,500 | 25.1 / 31.6 MB | id **26% more** on average |
| GloVe `id,embedding` | 40 | 7–10 | 281,083 | 115.1 / 123.2 MB | id **7% more** on average |

For the small projection, every paired query scans **the same number of rows** under `rowid` and `id` despite different *listed* file counts. `id IN` reduces listed files, not meaningful logical bytes or latency here. It is plausible that the reader already avoids the unneeded row groups or that list count is not a physical-access count; the profiles alone cannot establish exact file-open or page-fetch behavior. For the embedding projection, much more data is read and returned, but `id` pruning does not save it; the reason for the counterintuitive byte direction was not isolated. A previous separately run, repeated oracle-ID `id,embedding` control also had `id IN` slightly slower than `rowid IN` (SIFT p50 28.6 vs 27.0 ms; GloVe 52.3 vs 51.5 ms). Do **not** present the one-off vector-profile times as stable performance numbers.

Representative small-projection profile reports binding ~1.0–1.3 ms and a parallel DuckLake scan. Scan operator CPU time is **summed over threads** and can exceed elapsed time; do not subtract it directly from p50 latency. The open [DuckDB Parquet page-index PR #27326](https://github.com/duckdb/duckdb/pull/27326) already targets a related page-skipping opportunity, increasing the prior-art/overlap risk of a generic Parquet point-lookup claim.

## Verdict and next falsification gate

1. **The easy client-call hypothesis failed locally.** Moving PDX into one SQL UDF did not remove most of the latency. This is useful but **not** a new mechanism or thesis result by itself.
2. **The file-count premise also failed for small warm-local payloads.** A new locator that only turns a 40-file plan into a 4–10-file plan is not justified. This is stronger than just saying an `id` rewrite showed no timing gain: matched profile data shows the same scanned rows and <~1.1% lower reported bytes.
3. **The residual cost is real but not yet specifically attributable to avoidable multi-file random reads.** Existing reader/Parquet row-group materialization, binding, metadata work and output projection may contribute. No safe new locator has been implemented or benchmarked. The larger embedding projection exposes more cost, but does not establish that a file-aware locator is the right remedy.
4. **C13 remains conditional, not MSc GO.** The next *single bounded test* must use at least two independently sourced workloads with genuine returned payloads, relevant filters/updates, and cold/remote access; instrument per-file/page requests and bytes. Compare the best legal existing-interface query with a lower-bound/oracle selective-fetch cost at the **same snapshot/output/recall**. If achievable savings are small or overlap the page-index work, stop File-Aware Materialization. Only if a substantial gap survives and a snapshot-correct low-intrusion path is source-proven should a C++ mechanism begin. Maintenance/index-generation cost and VSS/Lance same-semantics baselines remain mandatory before thesis GO.

## Reproduction and raw artifacts

All files are in this isolated directory; C17 was not edited. Failed smoke runs are preserved in `sql_cost_sift.log`, `sql_cost_sift_r1.log` and profile logs, with corrected scripts/results in `sql_cost_sift_r2`, `sql_cost_glove_r1`, `profile_pair_sift_r1`, `profile_pair_glove_r1`, `profile_pair_sift_vector`, `profile_pair_glove_vector`. `prepared_gate.py` and `prepared_{sift,glove}/report.json` archive the separate prepared-statement control.

```bash
cd <local-projects>/ducklake_vector_snapshot_gate_20261027
V=/tmp/vector-pdx-venv-20261027/bin/python
$V sql_cost_gate.py --dataset sift --out-dir NEW_sql_sift
$V sql_cost_gate.py --dataset glove --out-dir NEW_sql_glove
$V profile_pair_gate.py --dataset sift --out-dir NEW_profile_sift
$V profile_pair_gate.py --dataset glove --out-dir NEW_profile_glove
$V profile_pair_gate.py --dataset sift --projection vector --out-dir NEW_profile_sift_vector
$V profile_pair_gate.py --dataset glove --projection vector --out-dir NEW_profile_glove_vector
$V prepared_gate.py --dataset sift --out-dir NEW_prepared_sift
$V prepared_gate.py --dataset glove --out-dir NEW_prepared_glove
```

These require the previously archived immutable `/tmp/c13-vector-data`, `/tmp/c13-vector-probe-list` and `pdx_{sift,glove}/index.pdx`. Output directories must be fresh. Raw JSON contains query IDs, all measured runs, profile counters and full per-query profiles; `sql_cost_gate.py` checks row sets and PDX UDF call count. Current-main DuckLake source was separately audited, but executable measurements use the pinned 2.0.0/`417a9117f5` build.
