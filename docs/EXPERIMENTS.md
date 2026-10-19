# Experiment notes and limits

## Evidence groups

- `20261018_008`: pristine versus clean B-only candidate; ten SQL cases, OFF → ON → ON → OFF sessions, two warmups and nine formal runs per session, 360 formal timing rows. Includes full-row generated TPC-H SF1/SF3, adapted public Dutch rail records, and negative controls. The rail query was adapted for diagnosis; it is not a sourced production SQL. The DuckDB-published full-row Top-N query is **not** a standard TPC-H benchmark query.
- `20261018_009`: four-arm BASE / A / B / A+B factorial, 576 formal timing rows. The field-consumer and whole-row workloads show that A and B target different costs. This is a diagnostic combined build, **not** a recommendation to multiply separate speedups.
- `20261018_011`: clean B-only boundary supplement, 252 formal timing rows across seven new SQL/parameter cells. SF1 full-row K30 is 1.44× and the four-thread K30 control is only 1.10×. An offline 27-byte saved-sort-key-per-input threshold was a diagnostic proxy, not a runtime selector; K100 was a training false positive.

All timings include SQL parse/plan, execution and complete in-process Fetch, but exclude database import, process startup, profiling and file output. Physical plans and result signatures were checked separately. Formal timing binaries were uninstrumented; diagnostic counters and profiler captures were not treated as precise wall-time decomposition.

## Interpretation boundaries

- A's 16→4 scan columns is a plan observation; its end-to-end gain also includes less `STRUCT` construction and aggregate work. Do not assign the entire gain to scan alone.
- B's saved payload encoding is supported by the unchanged plan and diagnostic/profile evidence; CPU sampling is not precise wall time, and an `ldr` instruction is not a cache-miss measurement.
- The CSV `loaded_lib_role` field is a public redaction of local absolute library paths. All timing, row-count and result-fingerprint values are unchanged; CSV line endings were normalized to LF. The original local files and profiler traces remain archived in the local research workspace, not on GitHub.
- Generated TPC-H and one adapted public-data query demonstrate opportunity but not prevalence among production OLAP queries. Results are from one Apple Silicon machine. There is no cross-architecture validation or formal full-SQL correctness proof.
- A's Top-1 foundation has prior art in DuckDB PR #20245. B's scope is Top-K fallback `STRUCT` payload preparation on the pinned baseline, not a claim that all upstream versions lack any related optimization.
