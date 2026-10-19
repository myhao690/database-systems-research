# Current-code naming cleanup (2026-10-19)

This is a naming and compatibility update, not a new optimization or a performance experiment. The original A/B research commits and all published timing data remain unchanged.

- A C++ helpers, helper type and state members no longer carry a project prefix. The preferred OFF-by-default switch is `DUCKDB_TOPK_PAYLOAD_PRUNING=1`. `C17_ARGMAX_PAYLOAD_PRUNING=1` remains a legacy alias for archived drivers; an explicitly set new switch takes precedence, including `0`.
- The A SQLLogicTest files are now `arg_max_struct_payload_pruning.test` and `arg_max_struct_payload_pruning_multifield.test`. Test-local fixture tables have descriptive names.
- B's C++ algorithm is unchanged. Its `arg_max_selective_struct.test` fixture table has a descriptive name.
- Historical experiment reports, raw CSVs, original commits and source snapshots are intentionally not rewritten. Their old names are provenance, not current implementation symbols.

## Validation performed

Both variants were built with the existing Release `-O3 -DNDEBUG` configuration. The A SQLLogicTests passed with the new switch ON, both switches absent, and only the legacy switch ON: 71 assertions in 2 cases for each mode. The B targeted test passed: 42 assertions in 1 case.

The wider A optimizer suite passed 5,766 assertions in 137 cases, with 2 dependency-gated tests skipped. The wider B aggregate suite passed 7,265 assertions in 114 cases, with 5 dependency-gated tests skipped. No failed assertion was omitted.

An `EXPLAIN` smoke test of a grouped Top-2 `arg_max(struct_pack(extra, q), score, 2)` query with only `q` consumed showed:

| Environment | Scan projections |
|---|---|
| Neither switch set | `grp, extra, q, score` |
| New switch `=1` | `grp, q, score` |
| Legacy switch `=1` only | `grp, q, score` |
| New switch `=0`, legacy switch `=1` | `grp, extra, q, score` |

Both regenerated net patches applied cleanly to the unmodified baseline and produced Git trees identical to their respective A/B branch heads. These checks verify the naming transition and relevant behavior, not the absence of every possible DuckDB bug. Performance was not remeasured after the naming update.
