# Avoiding Unnecessary Payload Work in Grouped Top-K Aggregation in DuckDB

Two **independent** research patches for DuckDB's grouped `arg_max`/`max_by` Top-K execution. Both are evaluated against the same unmodified DuckDB source tree at [`f2b0bad0`](https://github.com/duckdb/duckdb/commit/f2b0bad0eb3e47e2060f1f07af9d2069eaf77ea1):

- **A — optimizer field pruning:** avoid scanning and constructing `STRUCT` fields that downstream consumers never read.
- **B — admission-aware encoding:** avoid preparing expensive payload sort keys for Top-K candidates that cannot enter the heap, while retaining batched encoding.

This is an independent research snapshot, **not** an official DuckDB release. A and B live on separate branches; neither is enabled by checking out `main`, and their reported speedups must not be multiplied.

## Repository layout

| Branch | What it contains | Start here |
|---|---|---|
| [`baseline-f2b0`](https://github.com/myhao690/database-systems-research/tree/baseline-f2b0) | Unmodified DuckDB source baseline | Upstream engine and tests |
| [`optimizer-field-pruning`](https://github.com/myhao690/database-systems-research/tree/optimizer-field-pruning) | Patch A and its SQLLogicTests | [`remove_unused_columns.cpp`](https://github.com/myhao690/database-systems-research/blob/optimizer-field-pruning/src/optimizer/remove_unused_columns.cpp) |
| [`execution-admission-aware-encoding`](https://github.com/myhao690/database-systems-research/tree/execution-admission-aware-encoding) | Patch B and its SQLLogicTest | [`arg_min_max.cpp`](https://github.com/myhao690/database-systems-research/blob/execution-admission-aware-encoding/extension/core_functions/aggregate/distributive/arg_min_max.cpp) |
| `main` | This guide, [`docs/`](docs/), [`evidence/`](evidence/) and portable [`patches/`](patches/) | **Engine source here is baseline, not A or B** |

To review a change, select its branch and compare it with `baseline-f2b0`, or open its net patch in [`patches/`](patches/). For the call path, use [`docs/CODE_STUDY.md`](docs/CODE_STUDY.md); for commit/tree provenance, use [`docs/PUBLISHED_COMMITS.md`](docs/PUBLISHED_COMMITS.md). The repository is a source snapshot rather than a fork containing DuckDB's full Git history.

## A — consumer-driven `STRUCT` field pruning

**Avoided work.** A supported downstream `list_transform(topk, lambda x: x.field)` may consume only part of an `arg_max(struct_pack(...), score, K)` result, yet the unmodified plan still reads and constructs the full payload. A propagates static field demands through supported projection aliases, unions multiple consumers' demands, and rebinds a narrower `STRUCT`/aggregate/Lambda expression. Whole-value consumers and unsupported forms fall back. In the measured one-field query, the scan projection changed from **16 columns to 4**; the end-to-end gain is not attributable to scan alone.

**Scope.** Built-in `arg_max`, deterministic `struct_pack`, static Lambda field access and the supported Top-1/Top-K paths. This is not general nested-column pruning. The Top-1 foundation overlaps [DuckDB PR #20245](https://github.com/duckdb/duckdb/pull/20245); the scoped extension here covers Top-K `LIST<STRUCT>`/Lambda demand and supported multi-consumer propagation. A is **OFF by default** and is enabled with `DUCKDB_TOPK_PAYLOAD_PRUNING=1` before process start. See the [current interface](docs/CURRENT_INTERFACE.md) and [A regression tests](https://github.com/myhao690/database-systems-research/tree/optimizer-field-pruning/test/sql/optimizer).

**A-only results.** Median complete SQL wall time; baseline and A are from the same [four-arm experiment](evidence/20261018_009/summary.csv). Times include parsing, planning, execution and complete in-process result fetching.

| Workload | Baseline | A | Speedup |
|---|---:|---:|---:|
| [SF1, Top-3, one consumed field](evidence/20261018_009/sql/field_sf1.sql), 1 thread | 2339.53 ms | 677.83 ms | **3.45×** |
| Same SQL, 4 threads | 524.41 ms | 198.96 ms | **2.64×** |
| [SF1, Top-3, multiple consumed fields](evidence/20261018_009/sql/multifield_sf1.sql) | 1938.93 ms | 1187.49 ms | **1.63×** |
| [SF0.1, whole-value consumer](evidence/20261018_009/sql/whole_fallback_sf01.sql) | 146.67 ms | 146.68 ms | **1.00×** |

The last row is an intentional fallback control, not a speedup claim. The SQL uses generated TPC-H data but is **not** a standard TPC-H benchmark query. [Raw runs](evidence/20261018_009/raw_runs.csv) and [full summary](evidence/20261018_009/summary.csv) are provided.

## B — admission-aware batched payload encoding

**Avoided work.** For supported full-`STRUCT` Top-K aggregates, the original fallback can prepare payload sort keys before the heap rejects candidates. B checks heap admission conservatively, selects candidate lanes, calls `PrepareData` once for that batch, then retains the original `Insert` order. It does **not** narrow the scan, change the heap representation or change comparison/result semantics. The extra selection work has a cost, so low-rejection or narrow-payload workloads need not improve.

**Scope.** The eligible Top-K `STRUCT` fallback update path only; not a general aggregate fast path or runtime AUTO selector. Read [`ArgMinMaxNUpdate`](https://github.com/myhao690/database-systems-research/blob/execution-admission-aware-encoding/extension/core_functions/aggregate/distributive/arg_min_max.cpp), [`WouldAdmit`](https://github.com/myhao690/database-systems-research/blob/execution-admission-aware-encoding/src/include/duckdb/function/aggregate/minmax_n_helpers.hpp) and the [B regression test](https://github.com/myhao690/database-systems-research/blob/execution-admission-aware-encoding/test/sql/aggregate/aggregates/arg_max_selective_struct.test).

**B-only results.** Median complete SQL wall time; each row compares the unmodified baseline with B, never with A.

| Workload | Baseline | B | Speedup | Evidence |
|---|---:|---:|---:|---|
| Generated TPC-H SF1, [full-row Top-3](evidence/20261018_008/sql/full_row_sf1.sql) | 579.40 ms | 231.44 ms | **2.50×** | [Run 008](evidence/20261018_008/summary.csv) |
| Generated TPC-H SF3, same full-row Top-3 shape | 1906.52 ms | 789.56 ms | **2.41×** | [Run 008](evidence/20261018_008/summary.csv) |
| SF1, [full-row Top-30, 4 threads](evidence/20261018_011/sql/sf1_full_k30_t4.sql) | 449.06 ms | 406.46 ms | **1.10×** | [Run 011](evidence/20261018_011/summary.csv) |
| SF1, [narrow order-ID payload](evidence/20261018_008/sql/order_id_sf1.sql) | 56.09 ms | 56.25 ms | **1.00×** | [Run 008](evidence/20261018_008/summary.csv) |

The full-row shape uses generated TPC-H data but is **not** a standard TPC-H benchmark query. The last two rows illustrate B's boundary, not a universal benefit. [Run 008 raw samples](evidence/20261018_008/raw_runs.csv) and [Run 011 raw samples](evidence/20261018_011/raw_runs.csv) are available.

## Validation and reproduction

The archived measurements used Release `-O3 -DNDEBUG` on one Apple Silicon machine, with two warmups and nine measured runs per session, alternating/ABBA-style order and no outlier deletion. The published CSVs retain formal samples and result fingerprints; see [method and limitations](docs/EXPERIMENTS.md) and [data provenance](docs/EVIDENCE_PROVENANCE.md). The A/B four-arm study also found **non-additivity**: on the SF1 one-field query, A alone was 677.83 ms while A+B was 705.98 ms. A+B is diagnostic, not a third recommended branch.

The branch heads were rebuilt and related SQLLogicTests passed after the naming-only cleanup. For independent review, use **separate Release build directories** for A and B:

The later [same-SQL four-arm study](docs/JOINT_STUDY.md) tests baseline, A, B and their diagnostic combination on SF1/SF3 and an independent rail dataset. It confirms cases where B adds value after A, but also records monotone-score and four-thread cases with little or no B benefit. Its [raw samples and SQL](evidence/20261021_joint/) are published separately from the earlier A-only/B-only measurements.

```sh
# From the repository root: A
git switch optimizer-field-pruning
cmake -S . -B build/a-release -DCMAKE_BUILD_TYPE=Release -DBUILD_UNITTESTS=ON \
  -DCMAKE_CXX_FLAGS_RELEASE='-O3 -DNDEBUG'
cmake --build build/a-release --target duckdb unittest -j4
DUCKDB_TOPK_PAYLOAD_PRUNING=1 build/a-release/test/unittest '*arg_max_struct_payload_pruning*'

# B: independent build; do not reuse A's build directory
git switch execution-admission-aware-encoding
cmake -S . -B build/b-release -DCMAKE_BUILD_TYPE=Release -DBUILD_UNITTESTS=ON \
  -DCMAKE_CXX_FLAGS_RELEASE='-O3 -DNDEBUG'
cmake --build build/b-release --target duckdb unittest -j4
build/b-release/test/unittest '*arg_max_selective_struct*'
```

Large input databases, the original benchmark drivers and profiler traces are **not** published; [`evidence/`](evidence/) is a selected archive, not a one-command performance reproduction suite. The performance numbers predate the naming-only commits; no post-cleanup timing run is claimed. Results from one machine and selected workloads do not establish a general DuckDB speedup or production-workload prevalence.

## Attribution and license

Engine source is derived from [DuckDB](https://github.com/duckdb/duckdb) at `f2b0bad0` and retains its original [`LICENSE`](LICENSE) and notices. This personal research repository is not affiliated with or endorsed by the DuckDB Foundation. “DuckDB” is used descriptively; see its [trademark guidance](https://duckdb.org/trademark_guidelines).
