> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# C2.2 — INNER Hash Join RHS-output Gather elision

**Result:** On the real SF=0.1 self-join, Q1 COUNT-only improved from 60.945 to 44.053 ms median (**1.383×**). Q2, which needs `b.row_id`, stayed at 81.031 versus 81.508 ms (0.994×); no Q2 benefit is established. These are whole-SQL wall times, not isolated Gather times.

## Controlled change

The existing empty RHS projection map still means **ALL**. A separate join-local `right_projection_none` flag means **NONE**. It is opt-in via `C17_C22_RHS_ELISION=1` and currently selected only for a single equality-condition `INNER` comparison join with two direct logical table scans and no RHS column used above the join. This narrow direct-scan guard was necessary: the first broader version failed an existing nested-join binding test; the final version passes it. The flag is serialized with the logical comparison join and carried to the physical hash join. `FillProjectionMap` remains unchanged. No global `DataChunk` or projection-map semantics were changed.

When the ordinary INNER scan has zero RHS output columns, both output branches skip `GatherRHS` and explicitly set the result chunk cardinality to the number of matches. Build row storage, build key, hash directory, NEXT chain, probe enumeration, join type, and Q2's RHS payload path remain unchanged. This is an output-projection optimization, **not** a new hash-table layout or join algorithm. The special path is restricted to INNER in `NextInnerJoin`; other join types call their original Gather path.

## Path and correctness

Fixed direction (`disabled_optimizers='join_order,build_side_probe_side'`), one thread, same persistent database and same Release dylib in all four sessions. EXPLAIN shows `RHS Output: NONE` only for Q1 and probe-only `SUM(a.row_id)` under ON; Q2 retains `b.row_id` on the RHS with no marker. OFF plans have no marker. The right scan is the Build side in the fixed plan. The real-data Q1, Q2, and probe-only checks each produced **18,637,738** matches; both row-ID sums were **5,596,515,819,755**. ON Q1 `EXPLAIN ANALYZE` reports 18,637,738 Hash Join output rows. The new SQLLogic test covers duplicate multiplicity, no match, NULL, 3,000 matches spanning output chunks, probe-only detail, Q2 payload, and LEFT fallback. It passed OFF and ON (20 assertions each). The related hash-join test group reported 6 passed, 1 skipped because `tpch` is unavailable; no assertion failed. See `tests/` and `plans/`.

The C1 fixed-data path instrumentation established that this workload executes the ordinary chained Hash Join rather than Perfect Hash. C2.2 did not modify path selection, but did not add a fresh runtime ordinary/Perfect counter. Therefore ordinary-path continuity is strongly supported by identical data, plan, and unchanged path-selection code, not newly measured by a C2.2 counter. The optimization has **not** been validated as a general Perfect Hash change.

## Formal A/B timing

Four independent driver sessions in OFF→ON→ON→OFF order; 2 warmups and 9 measured runs per query/session. `raw_runs.csv` contains all **72** formal records with correctness checks. Each session used the same local `libduckdb.dylib` (path logged), changing only the process environment flag. No outlier was removed. `pre_final/` retains earlier provisional runs made before the final INNER-only branch guard; they are not included in these statistics.

| Query | OFF median ms (range) | ON median ms (range) | OFF/ON |
|---|---:|---:|---:|
| Q1 COUNT-only | 60.945 (57.556–89.306) | 44.053 (42.873–50.029) | **1.383×** |
| Q2 Build checksum | 81.031 (77.289–103.989) | 81.508 (76.558–96.991) | 0.994× |

Q1 session medians in execution order were 58.766, 44.637, 43.735, 61.517 ms. Q2 medians were 84.118, 78.994, 84.914, 79.926 ms. The Q1 gap survives the ABBA reversal; Q2 session variation is larger than its overall median difference. `paired_comparison.csv` aligns run indexes across adjacent opposite-mode sessions only as a sensitivity contrast, **not** a strict same-process pair.

## Interpretation and limits

The evidence supports a real Q1 benefit from avoiding unneeded RHS output work while preserving output cardinality. It does **not** prove the entire 16.9 ms median difference is the pure `GatherRHS` CPU cost: planning/output shape and cache behavior may also change. It does not isolate Build/Finalize/Probe costs, establish cache misses, or claim benefit for Q2, non-INNER joins, nested joins, or Perfect Hash. A runtime environment flag is experimental and only read once per process. Next step: validate plan-shape coverage and collect matched CPU profiles for Q1 OFF/ON before widening the optimizer rule; do not start a new layout algorithm from this result.

## Reproduction inputs

- Fixed commit/worktree and exact DB/library/driver SHA-256: `environment.txt`.
- Source and regression test patch: `rhs_output_none.patch`.
- Release build logs: `logs/build.log`, `logs/build_final.log`, `logs/build_final_2.log`; CMake cache in the worktree `build/c22`.
- Test, SQL correctness and plans: `tests/`, `plans/`.
- Raw and derived data: `raw_session_1.csv` … `raw_session_4.csv`, `raw_runs.csv`, `summary.csv`, `paired_comparison.csv`; regenerate derived files with `python3 analyze.py`.
- Driver source/build command: archived C1 `results/c1/experiments/20261014_003/sources/{c1_driver.cpp,build_driver.sh}`; the unmodified C1 driver was linked against this experiment's dylib and logs its loaded path.

To repeat without overwriting these files, run one command with a **new, nonexistent** directory: `sh run_abba.sh <local-projects>/C17/results/c2/experiments/<new_id>`. The runner uses the archived driver and fixed database, refuses an existing destination, runs the four sessions, and regenerates raw/summary/contrast CSVs. Rebuild first if the linked worktree dylib is no longer present.
