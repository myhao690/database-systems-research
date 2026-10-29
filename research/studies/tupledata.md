> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# Post-#27733 TupleData CPU gate and upstream decision (2026-10-25)

**Decision:** do not implement another generic `TupleDataAllocator::Build`/variable-FastPath optimization. The existing #27733 patch remains a separately credited **bug-fix** candidate, not the novel C component of a thesis. This decision is limited to the tested source revision and workloads; it does not claim that all TupleData costs are negligible.

## What was measured

Pinned DuckDB `main`: `1641475ef1db08ec063631ff6a8f08d9d6736ae7`. Reused the existing #27733 patch and 200M-row persisted fixture; no new optimization source was written. An isolated diagnostic worktree was rebuilt in Release with only 1-in-64 per-thread sampled `std::chrono::steady_clock` timing around `TupleDataAllocator::Build` plus an all-call counter. The combined diagnostic diff and runner reproduce this measurement; diagnostic CLI SHA-256 `7c37f22f2d5f528992030e1de2d8b95fcb65fc627a45532557c3c63229b8ed7e`. Five fresh-process runs per shape, DuckDB 8 GB, `k<5M` (10M selected rows), no physical Spill. Full raw rows and DuckDB JSON profiles are retained.

The estimate is `sampled wall ns × (all Build calls / sampled Build calls)`, summed over threads. The comparison denominator is DuckDB's `query.cpu_time`; **this ratio is not a precise CPU attribution**: sampled wall may include scheduling/wait, the 1-in-64 periodic sample may alias patterns, and instrumentation remains. It is a bounded diagnostic gate, not a Release A/B speedup measurement. In particular, it does not measure all allocator methods, external sorting reorder, or memory allocator time outside `Build`.

| Post-fix shape | Median Build calls | Median estimated total Build thread-wall | Median query CPU | Median ratio; five-run range |
|---|---:|---:|---:|---:|
| High-cardinality VARCHAR `GROUP BY`, 8 threads | 1,163,850 | 0.124 s | 2.899 s | **4.41%**; 3.23–5.17% |
| VARCHAR hash join, 8 threads | 1,560,203 | 0.104 s | 6.628 s | **1.64%**; 1.46–1.69% |
| Ordinary VARCHAR `ORDER BY` CTAS, 8 threads | 195,314 | 0.016 s | 2.787 s | **0.54%**; 0.43–0.76% |
| High-cardinality VARCHAR `GROUP BY`, 1 thread | 48,918 | 0.008 s | 1.191 s | **0.69%**; 0.62–0.74% |
| VARCHAR hash join, 1 thread | 1,560,203 | 0.090 s | 4.386 s | **2.02%**; 1.98–2.11% |

The large call count was misleading as a CPU signal. A first diagnostic build placed many atomic counters in the hot loop and yielded apparent Build/query-CPU ratios of 18.79% for 8-thread aggregate and 5.81% for 8-thread join (raw, combined diagnostic diff, runner). The low-overhead remeasurement above reduced these to 4.41% and 1.64%. The counter-heavy build must **not** be used for performance conclusions.

## Opportunity decision

The metadata mechanism is real in both aggregation and join: the earlier counters found ~1.18M and ~1.55M reused ChunkParts in those two VARCHAR shapes. But after the existing #27733 fix, `Build` is not a strong **shared CPU hotspot**, and ordinary Sort takes a different, mostly FastPath physical layout. Even a hypothetical zero-cost `Build` would have limited query-wide upside in the measured join/sort cells. A variable-layout FastPath is already proposed by the issue reporter, so implementing it on these facts would neither establish novelty nor satisfy the user's multiple-workload net-benefit gate. **No new FastPath/batching/materialization patch was made.**

This does not exclude a future distinct C candidate discovered elsewhere (e.g. another independently profiled allocation or pinning cost), but that would require a new source-local profile and multi-workload controlled A/B before implementation. Repeated threshold/Mode searches are stopped.

## Existing #27733 bug-fix gate

The unchanged four-file candidate fixes a wrong heap-offset comparison and reuses one removed part per segment. Its strongest demonstrated value remains one previously failing 200M-row/100M-group query completing within a Linux 2 GiB hard cap and DuckDB 500 MB budget; this is **completion under a constrained memory budget**, not proof of generally lower RSS or faster queries. The issue reporter already described both ideas, so any upstream work must explicitly credit and coordinate with them.

Targeted safety validation **passed locally**: Release exact tests 13/13; five custom SQL stress cases correct, including four with actual Spill across Agg/Join/Sort/Window; forced 1 MB OOM followed by same-connection recovery; and Debug ASan+UBSan targeted tests 13/13 with no diagnostics. The candidate source remained unchanged. This is a meaningful engineering gate, **not full upstream merge readiness**: Apple arm64 LeakSanitizer was unavailable, TSan/full CI/cross-platform checks were not run.

**PR preparation may proceed** as a credited bug-fix contribution, but **merge-ready Go only if** a broader interleaved Release guardrail finds no material normal-path regression, full relevant DuckDB CI and concurrency/portability checks pass, and the issue has not gained a superseding upstream PR. A local patch plus one OOM rescue alone does not mean upstream acceptance or a novel thesis core.

**Thesis conclusion:** A/B remain the defensible optimization core. #27733 can be a valuable credited bug-fix case study/engineering contribution, but it should not be relabelled as an original general C. The proposed three-part “Eliminating Redundant Work and Memory Overhead” story is not yet supported by an independent cross-operator C patch.
