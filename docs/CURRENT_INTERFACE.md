# Current Top-K research interface

The active research branches are independent: A is optimizer-side field pruning; B is execution-side admission-aware batched encoding. Neither is merged into the other or into the `main` engine source tree.

## A: optimizer-field-pruning

The optimization is OFF by default. Set `DUCKDB_TOPK_PAYLOAD_PRUNING=1` before starting DuckDB to enable it. An absent variable or any value other than exactly `1` leaves it OFF. No earlier project-specific switch is recognized by this branch head. All current A SQLLogicTests use descriptive file and fixture names.

## B: execution-admission-aware-encoding

The B branch retains its existing eligibility checks and has no A optimizer switch. Its Top-K test uses a descriptive fixture name. No algorithm or result semantics changed during the naming cleanup.

## Validation of the current branch heads

Both branches used Release `-O3 -DNDEBUG` builds. A's two focused SQLLogicTests passed with the new switch ON, OFF and an obsolete switch set alone: 71 assertions per mode. The wider optimizer suite passed 5,766 assertions in 137 cases, with 2 dependency-gated cases skipped. B's focused test passed 42 assertions; its wider aggregate suite passed 7,265 assertions in 114 cases, with 5 dependency-gated cases skipped.

For a grouped Top-2 `arg_max(struct_pack(extra, q), score, 2)` query consuming only `q`, `EXPLAIN` showed scan projections `grp, q, score` with the new switch enabled, and `grp, extra, q, score` with the switch absent or with only the obsolete switch set. Both net patches applied to the unmodified baseline and produced trees identical to their respective branch heads.

These checks verify the current interface and related SQL behavior. They are not a full DuckDB test run or a new performance measurement. The published timing evidence predates this naming-only change; its source queries and result values were not altered.
