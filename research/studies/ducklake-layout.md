> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# DuckLake physical-layout feasibility gate (2026-10-27)

## Decision

**No-Go for implementing a general adaptive reclustering mechanism using existing DuckLake maintenance APIs now.** This is a feasibility gate, not a final scientific rejection of the broader thesis. The real snapshot is too small and has no genuine evolving query log; a larger, independent, timestamped workload is needed before committing to a full MSc thesis. Do not turn these measurements into a performance claim or an upstream PR.

## Reproduction

- DuckDB Python 2.0.0, DuckLake extension hash `417a9117f5`, DuckLake catalog 1.1, macOS ARM64, 4 threads.
- Source: `results/opportunities/experiments/20261015_001/data/entur_realtime.parquet`, SHA-256 `65873a3b3165bb80f56763e3aaf7b3de6352b8893f08f7139f3ac0eba694cc87`. Source is an issue-author-hosted derived Entur snapshot; its redistribution licence is uncertain; **do not publish the Parquet or derivative DuckLake files** without permission.
- Run `./results/ducklake_layout_gate_20261027/reproduce.sh`. It installs DuckDB 2.0.0 into a temporary directory, not the system environment. The DuckLake catalogs and full raw timing JSON are written to fresh temporary directories; this directory archives the original raw timing JSON and scripts.
- Each test replays four chronological batches into four layouts: natural input order, timestamp sort, lineRef sort, timestamp-to-lineRef sort switch after batch two. Three filter queries are interleaved randomly 18 times each. Maintenance `ducklake_merge_adjacent_files` is run after the initial timings, at a 4 MB target. All answers were equal across layouts.

## Measurements (warm local-cache p50; milliseconds)

| Corpus/layout | Insert total (s) | Time filter | `SKY:Line:1` | `RUT:Line:31` | Initial files | Merge cost (s) |
|---|---:|---:|---:|---:|---:|---:|
| Real 630,103 / natural | .241 | 2.88 | 3.26 | 3.13 | 8 | .077 |
| Real / time | .270 | 3.04 | 3.21 | 2.99 | 8 | .099 |
| Real / line | .292 | 3.02 | 2.93 | 2.83 | 8 | .099 |
| Real / switch | .291 | 3.07 | 3.02 | 2.96 | 8 | .110 |
| Scaled 5,040,824 / natural | .166 | 3.13 | 5.62 | 4.98 | 12 | .143 |
| Scaled / time | .416 | 3.19 | 4.91 | 5.01 | 12 | .172 |
| Scaled / line | .550 | 3.80 | 3.13 | 3.05 | 12 | .195 |
| Scaled / switch | .500 | 3.23 | 4.02 | 4.05 | 12 | .229 |

The scaled rows are eight copies of each real record; they are **not independent data**. They only show that more rows/files can expose a filter-layout tradeoff. The synthetic scaling also changes compression and file sizes; do not extrapolate to production. In the real snapshot, differences are mostly sub-millisecond and too small to justify a mechanism. In scaled data, fixed line sorting already beats switching on line filters before compaction; fixed natural order beats switching on time filters. Query timings are *before* maintenance. Full per-run values and p95 are in the JSON files.

On the scaled catalog, after compaction the file counts fell from 12 to 3 per table, with costs of 0.14–0.23 s. The switch table's active bytes rose from 12.4 MB to 31.7 MB because of the artificial repeated data and rewrite; old files remain scheduled for deletion until cleanup. Post-maintenance warm-cache medians were time 3.20/3.20/4.37/3.97 ms and `SKY:Line:1` 5.29/5.25/3.36/3.34 ms in natural/time/line/switch order. Those raw runs are in `scaled_report.json`; they were obtained in a separate process after the original test.

Actionability probe: after setting the switch table's sort key back to timestamp, calling `ducklake_merge_adjacent_files('lake','switch')` again returned **zero operations**, with 3 files and 31,651,822 active bytes unchanged. An ALTER of the sort key does not itself reorganize existing full-sized files. This is expected from the documented compaction eligibility rules; it is not a bug claim.

## Evidence boundary and next gate

This test does **not** have real query arrival rates, workload drift, object-storage I/O, independent corpora, actual bytes read, statistically reliable speedups, or throughput under concurrent maintenance. It cannot establish sustained net value. It does establish that the current API does not offer an unconditional cheap way to change old layout and that a small real snapshot gives almost no headroom.

A thesis commitment should require a larger independent dataset with time-ordered writes **and an independent query trace**; a strong static layout baseline; an offline adaptive upper bound accounting for writes, rewrites, snapshot retention and catalog costs; and repeated net-benefit results. If the upper bound fails to beat fixed layouts or requires a new general rewrite primitive, stop this branch rather than narrowing to a threshold tweak.
