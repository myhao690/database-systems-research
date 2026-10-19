# Source-reading map

Both branches start from DuckDB `f2b0bad0eb3e47e2060f1f07af9d2069eaf77ea1`. Switch branches before opening the paths below: identical path names can contain different code.

## A: optimizer field demand

1. `src/optimizer/remove_unused_columns.cpp`: eligibility and lineage helpers (`C17EligibleTopK`, `C17CollectTopKLineage`).
2. `RemoveUnusedColumns::VisitExpression`: recognize supported `list_transform` Lambda extraction and register field demand without elevating the whole `LIST` to a full-value demand.
3. Projection and Aggregate branches: propagate demands through simple aliases, union multiple consumers, detect whole-value users.
4. `C17TryPruneTopKImpl`: build a narrower `struct_pack` in original field order, rebind `arg_max`, `struct_extract`, Lambda and `list_transform`, then commit only after successful preparation. A narrowed `STRUCT` must remain a `STRUCT`; replacing it with a scalar changes NULL semantics.
5. Test both `c17_argmax_payload_pruning.test` and `c17_argmax_payload_pruning_multifield.test`; unsupported forms must fall back.

## B: execution-side admission and encoding

1. `extension/core_functions/aggregate/distributive/arg_min_max.cpp`: read the pristine `ArgMinMaxNUpdate` before the B diff. `inputs[0]` is return payload; `inputs[1]` is score.
2. `src/include/duckdb/function/aggregate/minmax_n_helpers.hpp`: read `WouldAdmit`, `Insert` and `MinMaxFallbackValue::PrepareData`. The original fallback prepares temporary sort keys before rejection is known.
3. In the B branch, follow eligibility → 32-lane profitability sample → conservative `SelectionVector` → one batched `PrepareData` → original-order `Insert`. Distinguish original input lane from candidate-vector lane.
4. The pre-chunk heap threshold is conservative: after insertion, a full top-K threshold for `arg_max` cannot decrease. A prefiltered-out row therefore cannot become admissible later in the chunk. Selected rows may still be rejected by a later `Insert`.
5. Test `arg_max_selective_struct.test`, including NULLs, ties, dynamic K, cross-vector state, parallelism and unsupported-type fallback.

A failed predecessor encoded admitted rows one by one and was slower due to per-row allocation/free overhead. B's central engineering lesson is to avoid useless payload work **without destroying the vectorized batch**.
