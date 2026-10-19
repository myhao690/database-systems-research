# Avoiding Unnecessary Payload Work in Grouped Top-K Aggregation in DuckDB

> **Independent research source snapshot**, not an official DuckDB project or an upstream performance claim. The baseline branch has the exact source tree of upstream commit `f2b0bad0...`, but this repository intentionally does **not** contain DuckDB’s full Git history. This repository contains two **separate** experimental C++ improvements on the same DuckDB baseline. It does not implement a Hash Join optimization or a universal runtime selector.

## Read this repository

| Branch | Purpose | Original local commit |
|---|---|---|
| [`baseline-f2b0`](../../tree/baseline-f2b0) | Unmodified DuckDB baseline | `f2b0bad0eb3e47e2060f1f07af9d2069eaf77ea1` |
| [`optimizer-field-pruning`](../../tree/optimizer-field-pruning) | **A:** consumer-driven `arg_max` Top-K `STRUCT` payload pruning | `64bedbc0e7becc41e9914ff57a502c8f7d5aa7a5` |
| [`execution-admission-aware-encoding`](../../tree/execution-admission-aware-encoding) | **B:** selective, batched Top-K payload sort-key encoding | `435d7a420d4a768e2f701c49a824b2682d57c1be` |
| `main` | This project guide, portable net patches and selected evidence; engine code is otherwise at the baseline | Publication commit |

The initial published A/B commits reproduce the **exact code trees** of the original local research commits while using a GitHub noreply author address. Subsequent commits remove project prefixes from current A implementation names and A/B SQL tests without changing either algorithm; all earlier commits remain in history. See [`docs/PUBLISHED_COMMITS.md`](docs/PUBLISHED_COMMITS.md) for SHA and tree mappings. A and B are **not** one default combined patch. Review each against [`baseline-f2b0`](../../tree/baseline-f2b0); the net patches are also in [`patches/`](patches/). The original DuckDB README is preserved on the [`baseline-f2b0` branch](https://github.com/myhao690/grouped-topk-payload-work/blob/baseline-f2b0/README.md).

### A — consumer-driven payload pruning

The optimizer recognizes a restricted static `list_transform(topk, lambda x: x.field)` consumer of a built-in `arg_max(STRUCT, score, K)`. It unions field demands across supported consumers and simple projection aliases, rebinds the narrower `STRUCT` payload, aggregate and Lambda types, then lets existing column pruning reduce scan width. Whole-value consumers and unsupported or semantics-sensitive forms fall back. Entry point: `src/optimizer/remove_unused_columns.cpp`; tests: `test/sql/optimizer/arg_max_struct_payload_pruning*.test` on the A branch. The Top-1 foundation overlaps prior upstream work in [DuckDB PR #20245](https://github.com/duckdb/duckdb/pull/20245); the Top-K `LIST<STRUCT>`/Lambda and multi-consumer propagation are the scoped research extension here.

This experimental A optimization is OFF by default. Set `DUCKDB_TOPK_PAYLOAD_PRUNING=1` before starting DuckDB to enable it. No older project-specific switch is accepted by the current branch head.

The current switch, branch boundaries and validation are recorded in [`docs/CURRENT_INTERFACE.md`](docs/CURRENT_INTERFACE.md).

### B — admission-aware batched encoding

For supported full-`STRUCT` Top-K aggregates, the update path estimates whether candidate rejection makes prefiltering worthwhile. It conservatively selects lanes using the heap admission predicate, encodes the selected payloads **once as a batch**, and still calls the original `Insert` in input order. It does not change scan projection, heap representation, comparison semantics, result type or plan shape. Entry points: `extension/core_functions/aggregate/distributive/arg_min_max.cpp` and `src/include/duckdb/function/aggregate/minmax_n_helpers.hpp`; test: `test/sql/aggregate/aggregates/arg_max_selective_struct.test` on the B branch.

## Selected evidence, not universal speedup claims

The measurements below predate the naming cleanup and are from fixed Release `-O3 -DNDEBUG` builds on one Apple Silicon machine. The renamed versions were rebuilt and their related SQL tests passed; performance was not remeasured. Timed queries used warmups, alternating/ABBA sessions, nine measured runs per session, in-process complete result consumption, and no outlier deletion. The published [`evidence/`](evidence/) includes selected SQL, all formal raw timing rows and summaries; absolute local library paths were replaced by variant labels in the public CSVs, with original file hashes documented in [`docs/EVIDENCE_PROVENANCE.md`](docs/EVIDENCE_PROVENANCE.md). Large database files, profiler traces and binaries are **not** committed.

| Workload | Native baseline | Relevant branch | Median SQL wall time | Observation |
|---|---:|---:|---|---|
| SF1 grouped Top-3, one downstream `STRUCT` field | 2339.53 ms | A: 677.83 ms | **3.45×** | Scan projection narrows 16 → 4 columns; four-arm experiment [`20261018_009`](evidence/20261018_009/) |
| DuckDB-published full-row Top-3 shape over generated TPC-H SF1 | 579.40 ms | B: 231.44 ms | **2.50×** | Full payload required; clean B-only experiment [`20261018_008`](evidence/20261018_008/) |
| Same full-row shape, SF3 | 1906.52 ms | B: 789.56 ms | **2.41×** | Scaling check; same B-only experiment |
| SF1 full-row Top-30 | 999.30 ms | B: 695.39 ms | **1.44×** | Larger K still benefits in this case; boundary experiment [`20261018_011`](evidence/20261018_011/) |

The A/B four-arm experiment also found **non-additivity**: for the SF1 one-field query, A alone was 677.83 ms and A+B was 705.98 ms. A zero-rejection B control had overlapping time ranges and no established benefit. These are scoped experimental facts, not claims that every grouped Top-K query or machine improves. See [`docs/EXPERIMENTS.md`](docs/EXPERIMENTS.md) for methods and limits.

## Reproduction and review

1. Start at the exact baseline SHA above. The branch heads contain the implementation and SQLLogicTests. Alternatively, apply **one** patch from [`patches/`](patches/) to a clean baseline; do not apply both when evaluating either contribution independently.
2. Read [`docs/CODE_STUDY.md`](docs/CODE_STUDY.md) for the call paths and correctness boundaries.
3. Read the SQL in [`evidence/`](evidence/) with the corresponding raw CSV and summary before interpreting the timing ratios. These public artifacts are a **selected archival subset**, not a one-command benchmark suite: the original local drivers and large input databases are not distributed here.

## Attribution and license

Engine source is derived from [DuckDB](https://github.com/duckdb/duckdb) at `f2b0bad0...` and retains its original [`LICENSE`](LICENSE) and notices. DuckDB is a trademark of the DuckDB Foundation. This personal research repository is not affiliated with or endorsed by the DuckDB Foundation. The name “DuckDB” is used descriptively. See the [upstream project](https://github.com/duckdb/duckdb) and [trademark guidance](https://duckdb.org/trademark_guidelines).
