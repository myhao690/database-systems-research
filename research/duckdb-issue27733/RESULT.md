> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# Upstream-first aggregate memory pivot (2026-10-25)

## Decision

Stop the compact-Spill-format branch as an upstream PR candidate. Also do not implement
early combine for [duckdb/duckdb#22474](https://github.com/duckdb/duckdb/issues/22474)
without a new reproducer: its published 1-billion-row, 2-million-group, 4-GB/8-GB,
3-thread failure reproduces in DuckDB 1.5.6 but **not** in upstream `main` at
`1641475ef1db08ec063631ff6a8f08d9d6736ae7`, even on the same v1.5.6-created
database. Main also completes a 2-billion-row version at 3 and 4 threads with zero
reported Spill. This is consistent with the upstream adaptive hash-table work
[#26166](https://github.com/duckdb/duckdb/pull/26166) and the closing comment on
[#23109](https://github.com/duckdb/duckdb/issues/23109). It does not prove that every
case described in #22474 is fixed.

Pursue a smaller and independently reproducible upstream defect instead:
[duckdb/duckdb#27733](https://github.com/duckdb/duckdb/issues/27733). `TupleDataChunk`
compares a heap block offset with a **block index** when deciding whether adjacent
variable-size parts can merge. Even when a part is merged away, its arena allocation
is not reused. This can grow non-spillable tuple metadata during VARCHAR-key hash
aggregation. The issue reporter identified and prototyped this direction; this local
candidate is **not** an originality claim or an upstream submission.

## Local candidate

- Clean baseline worktree: `../C17-DuckDB-Agg-Metadata-Baseline-20261025`, at
  `1641475ef1db08ec063631ff6a8f08d9d6736ae7`.
- Candidate worktree: `../C17-DuckDB-Agg-Compaction-Upstream-20261025`, same base
  commit, with only this patch in four files.
- Patch SHA-256: `3fd30e316438d4ace24d0e626f1d66bd58c240bf1090bb712bf6bd7463980e21`.
- Baseline CLI SHA-256: `22864a17aaf86e07f81f50f244da09444bee421fd27e5681886cc1123a589e9a`.
- Candidate CLI SHA-256: `f6e1821b22aa0561669c71e8954fb5ae54cae30ece28f7b3d980ba04cae0bc50`.
- Linux baseline/candidate CLI SHA-256: `afcee93743f56abc467e4e22b7c9f2dd8f9ac06b17cb42af51f8032928abd8a8` / `e2d1d8578bb7efb96c47ade7d3ef5fe508ac984d2da8845076cc9c9422963ea7`.

The change fixes the offset comparison and retains **one reusable removed part per
segment**. It does not add a new Spill format, conversion, admission threshold, or
parallel worker barrier. The new unit tests cover aligned and non-aligned heap parts
and bound the arena allocation across 8,192 one-row variable-size appends.

## Evidence, not extrapolation

All local runs used macOS arm64 Release CLIs, the *same* 200-million-row persisted
fixture with 100 million distinct keys, fresh DuckDB processes, and identical SQL for
each A/B cell. `memory_limit` is DuckDB's logical setting, **not** a process RSS or
cgroup cap. Raw logs and profiler JSON are in `raw/`.

| Workload | Baseline | Candidate | Supported reading |
|---|---:|---:|---|
| VARCHAR `GROUP BY`, 200M rows / 100M groups, 8 threads, 500 MB, 15 GB temp | OOM: 64 MiB allocation failed at 417.3/476.8 MiB | Completed, exact result `(100M groups, 200M rows, SUM(v)=99.9B)` | Fixed-logical-budget completion improvement. Baseline and candidate used the same grouping expression in the paired count-only run; candidate was also checked with the stronger SUM fingerprint. |
| Same full VARCHAR grouping, 1 GB, one run each | 33.88 s; peak temp 13.04 GB | 30.15 s; peak temp 12.12 GB | Directional only; one run cannot establish speedup. Both completed and matched fingerprints. |
| Full VARCHAR grouping, 4 GB, 3 runs each, interleaved | Median 9.36 s; median peak temp 10.31 GB | Median 8.81 s; median peak temp 10.10 GB | Preliminary ~5.9% latency and ~2% temp reduction; not yet a cross-machine or hard-RAM claim. |
| VARCHAR grouping, 40M selected rows / 20M groups, 8 GB, zero Spill, 3 runs each, interleaved | Median 1.56 s; median max RSS 6.55 GB | Median 1.23 s; median max RSS 5.90 GB | **No-spill benefit**, not a conversion tax, on this shape. More repetitions/platforms needed. |
| BIGINT grouping control, same 40M selected rows, 8 GB, zero Spill, 3 runs each | Median 0.47 s | Median 0.56 s | Potential short-query regression/noise. Must not claim neutral overhead yet. |
| BIGINT full grouping control, 200M rows, 8 GB, 3 runs each | Median 3.26 s | Median 3.40 s | ~4% directional regression with wide run-to-run variance; needs a guardrail before PR. |

No universal peak-RSS reduction is established: 1-GB single runs had **higher** max
RSS for the candidate (5.36 vs 4.70 GB), and 500-MB candidate max RSS varied from
about 3.9 to 6.0 GB. The reduced arena growth is local to the tuple metadata; it
does not impose a hard bound on the whole process. The zero-Spill VARCHAR A/B had
similar query-wide cumulative allocation (6.09 vs 6.12 GB median), so this is not
evidence of a general cumulative-allocation reduction.

### Fixed-key performance guardrail follow-up

A further 10-pair macOS fresh-process run used the same
fixture and selected 40M-row query without profiler overhead. Median BIGINT-key
latency was **0.484 s baseline vs 0.464 s candidate**; the earlier 3-pair
0.47/0.56 s regression did **not** reproduce. VARCHAR-key medians were 1.855 vs
0.872 s, but baseline varied widely (1.07–3.04 s), so this is a local signal,
not a portable speedup estimate. All 40 result fingerprints matched. The per-run
logs are in `raw/mac_guardrail_10x.json`. The earlier
profiled 40M-row run reported zero Spill; this no-profiler follow-up did not
independently measure Spill.

## Linux hard-RAM gate

The same persisted 200M-row/100M-group VARCHAR fixture and COUNT+SUM SQL ran in
Linux arm64 Docker containers with `--memory=2g --memory-swap=2g`, 8 threads, and
15 GB DuckDB temp quota. Source for both Release builds was the same pinned main
commit; the container could not resolve the host git-worktree pointer and CMake
printed a dummy internal git hash. The harness and each
`result_linux_*.json` / profiler / query log are archived. These are
**single A/B runs**, not throughput distributions.

| DuckDB `memory_limit` | Baseline | Candidate | Interpretation |
|---|---|---|---|
| 500 MB | Failed after 11.7 s with DuckDB's own 476.6/476.8 MiB pin-allocation error | Completed in 48.7 s; exact `(100M, 200M, 99.9B)` | **A real fixed-hard-RAM completion gain** for this workload: both had a 2 GiB cgroup cap and neither had a cgroup OOM kill. It does not imply a lower peak process RAM. |
| 1 GB | Completed in 45.7 s | Completed in 47.7 s | No Linux speedup in this pair; candidate was ~4.5% slower. Max child RSS was 1,232,524 vs 1,191,016 KiB (~3.4% lower for candidate), but one run is not a robust peak-RAM claim. |

The 2 GiB cgroup `memory.peak` reached the cap in **all four** runs. Sampled
`memory.stat` showed substantial `file` usage alongside anonymous memory,
consistent with cache pressure; `memory.events` recorded `oom=0` and
`oom_kill=0` throughout. At 500 MB the
candidate's max child RSS was **higher** than the failing baseline (896,276 vs
751,228 KiB); the baseline stopped early. At 1 GB the Linux candidate spilled
4.56 GB vs 4.54 GB baseline and allocated 30.61 GB cumulatively vs 30.48 GB,
so this pair does not support a disk-I/O or allocation-volume reduction. The
credible benefit is elimination of a non-spillable metadata bottleneck, allowing
completion at the same logical and hard resource limits. It is not a general
memory cap or a guaranteed speedup.

## Verification

- Candidate Release CLI and `unittest` built successfully.
- `[tuple_data_allocation]`: **4/4** tests, **230,535** assertions passed on the final patch after rebuilding `unittest`.
- `test/fuzzer/duckfuzz/tuple_data_empty_heap.test`: passed.
- `test/sql/aggregate/*`: **245/245** cases, **258,799** assertions passed; optional
  `tpch`, `tpcds`, and `longdouble` cases skipped by test prerequisites.
- `git diff --check` and `clang-format --dry-run --Werror` passed on changed files; the archived patch passes `git apply --check` against the clean baseline.
- Candidate and baseline full-query COUNT/SUM result fingerprints matched wherever
  both completed; the 500-MB candidate result matched the 1-GB baseline result.

## Upstream readiness gate

**Promising local candidate, not yet PR-ready.** The Linux hard-cgroup completion
gate passed, but it does not prove lower peak RAM, better throughput, or lower disk
I/O. Before submission, measure peak `ALLOCATOR` by tag on this exact build,
repeat the fixed-width control across platforms and sizes (the macOS 10-pair
follow-up did not reproduce a regression), and test
inlined/long strings, NULLs, sort/join consumers of `TupleDataCollection`,
cancellation/OOM cleanup, and Debug/ASAN builds. Stop or narrow the patch if the
fixed-width regression is repeatable or the one-spare ownership invariant fails.
Because #27733 already proposes the same spare-part remedy, this should be treated
as an independently verified upstream fix candidate, **not** a novel doctoral
research mechanism or a claim of priority.

Reproduction SQL is in `reproduce.sql`. The 2.4-GB fixture and
temporary files are deliberately kept outside the repository at
`/tmp/c17_agg_metadata_20261025/` and are **not** part of this evidence archive.
