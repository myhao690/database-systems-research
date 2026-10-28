# A/B joint evaluation (2026-10-21)

This is a **separate experiment**, not an update to the earlier A-only and B-only numbers in the README. It uses identical diagnostic SQL across four independently built DuckDB Release `-O3 -DNDEBUG` libraries: baseline (`f2b0bad0`), A (`7c2a333`), B (`545c47d`) and A+B (`8cdadc7`). The A/B code matches the published branch heads' Git trees; A+B is an experimental composition, not a recommended third patch. The [B net patch](../patches/execution-admission-aware-encoding.patch) passes `git apply --check` on the A source tree.

## Result and boundary

Median complete SQL wall time in milliseconds, including parse, plan, execution, result fetch and result check. Each arm has ten formal runs per configuration, after two warmups per session; order was BASE→A→B→AB→AB→B→A→BASE. No samples were discarded.

| Diagnostic query | BASE | A | B | A+B | What it shows |
|---|---:|---:|---:|---:|---|
| SF1, part/price, width 16, K=3, 1 thread | 1252.75 | 424.30 | 987.70 | 364.67 | B adds ~1.16× over A here |
| SF3, same shape | 3939.16 | 1475.46 | 3121.60 | 1253.96 | B adds ~1.18× over A here |
| SF1, supplier/price, width 16, K=3, 1 thread | 632.37 | 123.00 | 264.47 | 85.41 | Larger groups help admission filtering |
| SF1, part/monotone score, width 16, K=3, 1 thread | 1938.87 | 675.61 | 1936.53 | 685.56 | B saves no meaningful work |
| SF3, part/price, width 16, K=3, 4 threads | 1723.84 | 606.83 | 1807.35 | 582.21 | B-only is slower; combined gain is uncertain |
| Dutch rail stops, station/delay, width 9, K=3, 1 thread | 114.01 | 37.37 | 35.81 | 17.29 | Positive result on another data source, but researcher-written SQL |

The complete 13-configuration matrix is in [summary.csv](../evidence/20261021_joint/summary.csv), with [520 formal samples](../evidence/20261021_joint/raw_runs.csv), [sequential adjacent comparisons](../evidence/20261021_joint/adjacent_comparisons.csv), [19 correctness/plan checks](../evidence/20261021_joint/correctness.csv), [group-size context](../evidence/20261021_joint/data_characteristics.csv) and [executed SQL plus independent window-ranking oracles](../evidence/20261021_joint/checks/). A+B gains are **not** the product of A-only and B-only gains. The monotone and parallel rows are retained as negative/boundary evidence.

## Provenance and limits

- The A/B and baseline source commits above are the exact versions used. The experimental A+B commit combines them; the A and B branches remain independent. Release libraries were built on one Apple Silicon/macOS machine with Apple Clang 21. Results were not rerun for this publication.
- Generated TPC-H SF1/SF3 data are used with **project-written diagnostic SQL, not standard TPC-H queries**. The rail table contains 1,902,543 records imported from [Rijden de Treinen's March 2025 services file](https://opendata.rijdendetreinen.nl/public/services/services-2025-03.csv.gz), licensed CC-BY-4.0; its query is also project-written, not an observed production query.
- The databases, executable benchmark driver, binaries, full profiles and machine-local logs are not included. The public SQL files are copied unchanged; CSV field values are unchanged and CRLF line endings were normalized to LF. Consequently this archive permits independent analysis of recorded samples but is **not a one-command performance reproduction**. Cross-machine speedups and production-query coverage remain unproven.
- Plan checks show A narrowed the measured scan (e.g. 16→3 columns); they do not isolate scan cost. B's diagnostic counters were collected with a different instrumented binary, not these timing binaries, so no byte-savings claim follows from this table alone.
