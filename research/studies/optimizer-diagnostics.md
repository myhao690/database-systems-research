> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# Direction 3 held-out gate: resource-aware OLAP diagnosis

**2026-10-28 decision: NO-GO as the core of a master's thesis, on present evidence.**
The recorder is a useful, reproducible diagnostic artifact. The held-out test
did not establish a new optimizer defect, a distinct causal diagnosis method,
or a repeatable cross-workload advantage over ordinary budget sweeps plus
`EXPLAIN`/profiling. No DuckDB patch was made.

## Pre-registered workload and boundaries

The held-out queries were TPC-H Q01, Q03, Q09, Q18, and Q21, copied without
query rewrites from `extension/tpch/dbgen/queries` in the local DuckDB source
at commit `6b6099a3e9787f1b32c59fab61fcdd1d3bc835cd`. They exercise
aggregation, joins, order/top-N, and subqueries. Each SELECT was wrapped as
`COPY (...) TO '/dev/null'` to force full execution without dumping results.
This wrapper's displayed count is **not** a correctness oracle. Q09's full
ordered result was checked separately below.

The databases were pre-existing C17 TPC-H SF1 and SF3 artifacts, opened
**read-only**. SHA-256: SF1 `7116d61733c56e589c01271e6b7197d3633028e983b54511c7cc9845e5777369`,
SF3 `705672a0a09b5eb7181f556f674e7d71d38929f4f7b6a77b04decc823ac8d3fa`.
All experiments used the same pinned Release DuckDB CLI
`1641475ef1db08ec063631ff6a8f08d9d6736ae7`, four threads, and memory
limits 256/512/1024 MB. The Mac's OS page cache was not reset; these are
warm-system measurements, not cold-I/O estimates. Cases and raw records are
in `cases/tpch_sf{1,3}/` and `runs/tpch_sf{1,3}_q*/`.

## Results

The first pass used two repetitions per query/scale/budget: **60/60
successful**. All three budgets had the same `EXPLAIN (FORMAT JSON)` operator
sequence for each query. SF1 had no spill and no credible memory-budget cliff.
This rules out neither other datasets nor other SQL; it only rejects a broad
claim based on this held-out set.

| SF3 query | 256 MB query-time median | 512 MB median | 1024 MB median | Main observation |
| --- | ---: | ---: | ---: | --- |
| Q01 | 62.5 ms | 64.1 ms | 62.4 ms | No spill; no meaningful effect in two runs. |
| Q03 | 41.7 ms | 44.1 ms | 42.2 ms | No spill; no meaningful effect in two runs. |
| Q09 | 208.6 ms | 152.2 ms | 151.8 ms | Candidate budget-sensitive slowdown; followed up below. |
| Q18 | 110.3 ms | 103.6 ms | 104.7 ms | At 256 MB: 21.2 MB peak temp directory, 8.45 MB cumulative spill; at larger budgets: none. Ordinary expected resource transition, not a novel regression. |
| Q21 | 90.7 ms | 84.0 ms | 83.4 ms | No spill; modest difference, only two runs. |

### Q09 follow-up: real effect, but no demonstrated optimizer bug

Eight alternating repetitions per budget were run both with and without the
DuckDB JSON profiler. The table uses wall time (which includes CLI startup)
for comparability across the two modes. Ranges are observed min–max, **not**
confidence intervals or reliable p95 estimates at n=8.

| Mode | Budget | Success | Wall p50 (range) | Process peak RSS p50 |
| --- | ---: | ---: | ---: | ---: |
| Profiled | 256 MB | 8/8 | 237.1 ms (224.4–243.3) | 322.9 MB |
| Profiled | 512 MB | 8/8 | 193.6 ms (187.1–205.6) | 545.2 MB |
| Profiled | 1024 MB | 8/8 | 192.4 ms (191.3–224.3) | 577.6 MB |
| Profiler off | 256 MB | 8/8 | 229.5 ms (225.6–251.8) | 322.0 MB |
| Profiler off | 512 MB | 8/8 | 188.5 ms (186.6–202.4) | 545.0 MB |
| Profiler off | 1024 MB | 8/8 | 190.1 ms (186.3–197.6) | 576.7 MB |

The profiled internal query-time medians were **202.1/156.0/154.7 ms**.
Profiler CPU-time medians were **0.731/0.578/0.577 s** (summed across
threads). The 256 MB run used less peak RSS but more CPU; `peak_temp_dir_size`
and `total_bytes_spilled` were **zero at all three budgets**. `EXPLAIN`
operator sequences matched. Aggregating reported operator timings across the
Q09 tree, `HASH_JOIN` accounted for ~0.560 s CPU at 256 MB versus ~0.402 s
at 512 MB; one join on `l_orderkey = o_orderkey` reported ~0.315 versus
~0.155 s. These operator timings are **summed CPU work, not critical-path
wall time**. Their correlation does not identify an algorithm switch or its
root cause; the memory limit may affect executor work without changing
`EXPLAIN`'s operator names. We must not label this an optimizer defect.

For a correctness spot-check, unwrapped Q09 returned 175 CSV rows at each
budget with the same SHA-256
`77b4302908f88dfa85f465797f599fe951c6dcd9c0c464f0453cb1c80b22eb57`.
This checks the observed result at these settings, not all TPC-H queries.
Raw check: `runs/tpch_sf3_q09_semantic_check.json`.

## Why the thesis gate fails

1. The only clear unexpected **failure** remains already-reported DuckDB
   [#26712](https://github.com/duckdb/duckdb/issues/26712), from the earlier
   pilot. Q09 is a repeatable resource/performance tradeoff, not a proven bug;
   Q18's spill is expected. There are not two independent, novel cases with
   distinct verified causes.
2. Our recorder performs the obvious baseline—budget sweep, static plan
   comparison, profile, and RSS. It has **not** beaten that baseline in
   execution count, diagnosis accuracy, or engineer time. Prior work on
   equivalent-query testing and optimizer ablation is described in
   PILOT_REPORT.md.
3. TPC-H SF1 and SF3 share one generator and query source. They are valuable
   controls, but not two independent real-data sources or evidence of broad
   production relevance.

**Stop condition reached:** Do not add a bespoke classifier, more optimizer
rule toggles, or a DuckDB patch merely to rescue the narrative. Retain this
repo as a portfolio-quality experimental harness. Reopen direction 3 as a
thesis core only if an externally grounded question supplies (i) at least two
independent verified failure mechanisms, (ii) a diagnostic intervention that
outperforms ordinary resource sweeps/profile on held-out cases, and (iii) a
clear upstream-facing system correction. Otherwise choose a different OLAP
research problem rather than treating a diagnostic script as the thesis.

## Reproduction

From this repo, using the pinned `BIN` in README.md:

```sh
for scale in sf1 sf3; do
  for q in 01 03 09 18 21; do
    python3 diag.py --case "cases/tpch_${scale}/q${q}.json" --cli "$BIN" \
      --out "runs/tpch_${scale}_q${q}_fresh" --reps 2 --timeout 90
  done
done
python3 diag.py --case cases/tpch_sf3/q09.json --cli "$BIN" \
  --out runs/tpch_sf3_q09_r8_fresh --reps 8 --timeout 90
python3 diag.py --case cases/tpch_sf3/q09.json --cli "$BIN" \
  --out runs/tpch_sf3_q09_noprof_r8_fresh --reps 8 --timeout 90 --no-profile
```

Output directories must not already exist. The absolute database path inside
each case file must be changed when reproducing on another machine. All raw
`runs.jsonl`, `summary.json`, `explain.json`, and per-run profiles are retained.
