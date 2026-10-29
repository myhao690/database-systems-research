> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# Real-workload gate for query-family optimization

**2026-10-28 verdict: PASS the workload-opportunity gate under a comparable
execution-thread budget; NO-GO for a C++ dynamic-admission prototype on the
current evidence.**
Two independent public dashboard sources contain naturally related query
families for which existing SQL-level reuse improves full-dashboard latency.
But materialization is already a simple manual solution, unconstrained
concurrency can be faster, and a static always-materialize policy nearly
matches the measured oracle. No automatic policy has yet been shown to add
value. This is **not** a thesis-success or novelty verdict.

## Sources and reproducibility

- DuckDB Release CLI source `1641475ef1db08ec063631ff6a8f08d9d6736ae7`
  (`v2.1.0-dev90061`), same binary used for the earlier synthetic probe.
- [ClickHouse simple logging benchmark](https://github.com/ClickHouse/simple-logging-benchmark),
  source commit `f55ff5f30ac03abbeda5994aa5a87c7fe4b03aae`: six dashboard
  drill-down states, seven panels each. Its public 66M-row CSV-gzip is
  `https://datasets-documentation.s3.eu-west-3.amazonaws.com/http_logs/data-66.csv.gz`,
  SHA-256 `4744be3b683db440b7b5636998a37de3ed29f764668cfe10829a082cff32647a`.
  A one-time DuckDB conversion to Snappy Parquet dropped 1,389 malformed
  UTF-8/CSV rows using `ignore_errors=true`: 66,747,274 rows retained from
  66,748,663 CSV data lines (~0.0021% omitted). Converted Parquet SHA-256
  `ecba8a64402ccfa29a418710702312ad25e3dcc7c45ceb30da45755ac80152fd`.
  The source itself replicates a shorter log period to one month; this is
  production-derived data, **not an unmodified production trace**.
- [NYC Rides × DuckDB dashboard](https://github.com/DirendAI/dashdown-parquet-1B-example),
  source commit `e875d87d156238ec43e43572d648117f6ccde1d4`: five panel SQL
  files using a common `ref('latest_union')` were tested on the *original*
  three NYC TLC Parquet files for July 2026 (24,492,548 selected rides). This
  one-month subset does not represent its full 1.6B-row published dashboard.
  SHA-256 for the downloaded July 2026 files: `yellow`
  `3260bb629c2f334055f8a566cbb02c15476b15120c45d7ad0aae46fc4bb06612`,
  `green` `1e01084ab77643cc94e53ad7c30163dd7e8ef0be7b5bbf62bd45c19b7580ee87`,
  `fhvhv` `8da280d9d23813aae02a6e1d1caa8b96eb5e8d38efcbc9a570faf1e418f5a8`.
  The `ref()` mechanism in the [Dashdown implementation](https://github.com/DirendAI/dashdown)
  at `d8b07f908ee33cb3b153e3b5ab61da5c4baa6ba9` compiles to inline SQL
  CTEs per query; it is not automatically one cross-query materialization.
- The C17 workspace and DuckDB source were not modified. Large datasets are
  ignored by Git; scripts, query expansions, raw timings, output hashes, and
  result checks are archived here. All runs are local macOS warm-system runs;
  no cold-cache, production arrival trace, or open-loop throughput claim.

## Full-dashboard results

All values are eight-run medians of complete dashboard wall time (CLI startup
and result delivery included). Arms were rotated within the logging experiment;
all seven adapted SQL outputs matched across arms in each repetition. The
translation intentionally uses DuckDB `count(DISTINCT ...)` instead of the
ClickHouse `uniq()` estimate, exact `quantile_cont` instead of ClickHouse
`quantile`, and stable tie-breakers for top-K. Therefore the result-equivalence
claim is **among adapted DuckDB arms**, not bitwise identity to ClickHouse.
The logging concurrency arm runs seven one-thread processes while the shared
arm uses one four-thread process: this is a *comparable*, not identical,
thread budget; no CPU-time equality is claimed.

| Logging state / selected rows | Seven serial (4 threads) | Seven concurrent (1 thread each) | Filtered temp table + seven panels (4 threads) | Gain vs concurrent |
| --- | ---: | ---: | ---: | ---: |
| Six hours / 904,567 | 127.6 ms | **119.7 ms** | 126.7 ms | -5.9% |
| + status 404 / 6,633 | 100.9 ms | 101.4 ms | **70.2 ms** | 30.8% |
| + path / 959 | 192.3 ms | 109.2 ms | **66.5 ms** | 39.1% |
| + IP / 5 | 130.2 ms | 59.2 ms | **50.8 ms** | 14.1% |
| + runtime / 3 | 135.4 ms | 58.9 ms | **51.7 ms** | 12.3% |
| Month zoom / 21 | 226.3 ms | 142.8 ms | **72.7 ms** | 49.1% |

The selectivity gradient **does not imply a monotonic gain**: once scans are
cheap and panel/runtime overhead dominates, materialization's incremental
advantage falls. For the six-hour broad case, it is slightly worse than
concurrent execution. Process peak RSS for the materialized arm was roughly
435 MB there versus 324 MB serial; at month zoom it was ~355 MB versus
~459 MB serial. The sum of individual peaks from seven concurrent processes
is only an upper-bound-like *sum*, not their simultaneous combined peak.
See `gate_logging_all6_r8/` for per-run data and exact adapted SQL.

The naturally compatible two-panel time-bucket family (`COUNT` and
`AVG`/p99) was separately tested with one fused aggregate. With an approximate
four-thread budget, fused vs two concurrent two-thread requests was 45.3 vs
56.6 ms for the broad six-hour stage and 63.1 vs 84.8 ms for month zoom.
That establishes a manual *pair* upper bound, **not** a whole-dashboard gain;
the seven-panel comparison above is the decisive application metric.

For the NYC dashboard, the five source queries each expanded the same
`latest_union` CTE. Results matched exactly when run against a one-time
materialized temp table. Eight-run medians:

| NYC five-panel mode | Complete-set wall time | Peak process RSS |
| --- | ---: | ---: |
| Serial, 4 threads | 1.946 s | 1.61 GB |
| Materialize once, then panels, 4 threads | **1.141 s** | **2.35 GB** |
| Five separate CLI processes, 1 thread each | 1.618 s | Individual peak RSS sums ~5.21 GB; not actual simultaneous peak |
| Five separate CLI processes, 4 threads each | **0.913 s** | Individual peak RSS sums ~5.53 GB; not actual simultaneous peak |

The concurrent results were measured in a separate eight-run cohort, not
interleaved with the serial/materialized pair, so the ratios are indicative,
not a paired significance test. Materialization is ~29.5% faster than
five one-thread queries with similar total worker count, but **slower** than
unconstrained five-by-four-thread concurrency. It also increases single-process
RSS by ~0.73 GB compared with serial. This is a real time/memory/parallelism
tradeoff, not a universally faster plan. See `gate_nyc_r8/` and
`gate_nyc_concurrent_r8/`.

## What the gate proves—and does not prove

**Proven:** there is cross-request redundancy in two independent public
dashboard sources. Under constrained, comparable execution-thread budgets,
existing SQL-level reuse can save >=20% complete-dashboard latency in
some naturally occurring states. Other states provide reproducible
counterexamples. This supports a *scenario-first* MSc question.

**Not proven:** a new optimizer, lower total CPU, true joint peak memory for
concurrent processes, improved QPS under arrivals, a globally optimal plan,
or benefit beyond hand-written temporary tables and fusion. Prior work already
studies concurrent analytical query sharing: [Psaroudakis et al. 2013](https://www.vldb.org/pvldb/vol6/p637-psaroudakis.pdf),
[Shared Workload Optimization](https://vldb.org/pvldb/vol7/p429-giannikis.pdf),
[Gurumurthy et al.](https://link.springer.com/article/10.1007/s10796-024-10506-w),
and [GraftDB (2026 preprint)](https://arxiv.org/abs/2606.04303). We must
not present multi-query sharing, CTE reuse, or dynamic folding as invented here.

**Static-policy check:** for the seven measured dashboard states (six logging,
one NYC), materialization is already the fastest of the two comparable-budget
arms in six. An always-materialize policy loses only 7.0 ms (5.9%) to
independent concurrency in the remaining broad logging state. Thus the
measured latency headroom for a dynamic admission policy over this simple
baseline is tiny. The NYC memory increase (~0.73 GB) may justify a resource
guard, but we have not shown that a nontrivial workload-adaptive rule beats a
plain memory cap or static materialization. No C++ admission patch is warranted
from these data alone.

## Revised thesis mechanism and next gate

The possible research question is **resource-bounded admission to an
ephemeral shared relation for a burst of related OLAP panels**. Start with
the dashboard's declared common base/filter and a safe per-request result
mapping; choose between independent concurrent, fused aggregate where exact,
and one-time temporary materialization. A first completed panel can reveal
actual qualifying-row count and scan cost without an extra sampling query;
whether that observation predicts the remaining-panel break-even remains
**untested**. Do not build a general optimizer or invent a new physical
operator before this mechanism is validated. In particular, the current
static-policy result is a stop signal for implementation, not an invitation
to tune another threshold.

Reopen a restricted C++ prototype only if a second, independent gate first
shows that static policies genuinely fail:

1. On the two public source suites, automatically choose the known good
   execution form in held-out states—not a per-state lookup table—and preserve
   all output/snapshot semantics.
2. Recover at least 80% of the manual oracle's latency gain while adding at
   most 5% to states where sharing should be rejected, under the same thread
   and RAM budget. These are project success thresholds, not universal laws.
3. Compare against the **simple** alternatives (static always-materialize,
   static always-concurrent, first-query materialization, prepared statements),
   not only independent serial execution. Report true system RSS/CPU and
   open-loop dashboard throughput before any thesis or upstream claim.

The present suite fails to establish the incremental opportunity required by
this gate. Finding one more favorable microbenchmark would not repair that;
the next evidence must be a naturally arising workload regime with a
substantial static-policy tradeoff under explicit RAM/CPU limits.

If a simple static policy performs equivalently, or the C++ mechanism only
automates a trivial SQL rewrite with no robust cross-workload advantage, stop
and classify this as useful engineering, **not** the thesis core.

## Commands

```sh
cd <local-projects>/olap_query_family_20261028
BIN=<local-projects>/C17-DuckDB-Agg-Metadata-Baseline-20261025/build/research-release/duckdb

git clone https://github.com/ClickHouse/simple-logging-benchmark logging_reference
git -C logging_reference checkout f55ff5f30ac03abbeda5994aa5a87c7fe4b03aae
git clone https://github.com/DirendAI/dashdown-parquet-1B-example nyc_dashboard_reference
git -C nyc_dashboard_reference checkout e875d87d156238ec43e43572d648117f6ccde1d4

# Data acquisition: original public files (download commands in the source
# dashboard READMEs). Pin the original month rather than re-running a
# moving "latest month" fetch:
mkdir -p data/nyc_latest
for kind in yellow green fhvhv; do
  curl -L --fail --retry 5 \
    "https://d37ci6vzurychx.cloudfront.net/trip-data/${kind}_tripdata_2026-07.parquet" \
    -o "data/nyc_latest/${kind}.parquet"
done
curl -L --fail --retry 5 \
  https://datasets-documentation.s3.eu-west-3.amazonaws.com/http_logs/data-66.csv.gz \
  -o data/logs_66m.csv.gz
shasum -a 256 data/logs_66m.csv.gz data/nyc_latest/*.parquet

# Convert the log CSV once, recording ignore_errors:
"$BIN" -no-agent -batch -bail :memory: -c \
  "COPY (SELECT time_local,remote_addr,runtime,request_type,request_path,status,size
          FROM read_csv_auto('data/logs_66m.csv.gz',ignore_errors=true))
   TO 'data/logs_66m.parquet' (FORMAT PARQUET,COMPRESSION SNAPPY,ROW_GROUP_SIZE 1000000);"

python3 logging_dashboard_gate.py --cli "$BIN" --parquet data/logs_66m.parquet \
  --out gate_logging_fresh --reps 8
python3 nyc_gate.py --cli "$BIN" --reference nyc_dashboard_reference \
  --data data/nyc_latest --out gate_nyc_fresh --reps 8
python3 nyc_concurrent_gate.py --cli "$BIN" --reference nyc_dashboard_reference \
  --data data/nyc_latest --out gate_nyc_concurrent_fresh --reps 8
```

The scripts refuse to overwrite existing evidence directories. The 2 GB log
download and original NYC Parquet files are not committed to Git; checksums
and source URLs pin them.
