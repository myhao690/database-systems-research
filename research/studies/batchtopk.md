> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# BatchTopK bounded feasibility gate — 2026-10-27

## Executive verdict

**NO-GO as an independent, excellent MSc thesis core under the proposed title
“A Memory-Bounded Vector Similarity Join Engine.”** A useful C++ engine is
technically plausible, but its defining features—IVF list-major batching,
blocked scoring, per-query bounded Top-K, and batch/execution memory control—
are largely established. A stricter *whole-process* RAM guarantee or a
Top-K-progress-aware scheduler might be differentiable, but neither has a
measured win nor a small verified implementation path. Stop before building a
production engine. This is not a claim that vector similarity joins have no
remaining research questions.

The novelty gate failed **before** a second-dataset or Faiss head-to-head
study. Those absent measurements are explicitly not evidence of broad
performance or competitiveness.

## Evidence from the isolated C++ gate

The source `src/c15_parallel_gate.cpp` runs the same pinned PDX IVF-F32 index
and query-to-centroid ordering for two paths: (1) per-query PDX iterative
search and (2) list-major, tile-64 gathered exact candidate GEMM with
per-thread Top-K heaps. Build: `cmake --build build --target c15_parallel_gate
-j 4`. Each process performs one warm-up and two timed iterations; the table
shows the median reported by the program. This is **pilot evidence**, not a
publication-grade randomized interleaved benchmark. Raw JSON is in
`results_parallel/` and exact commands in `REPRODUCE_PARALLEL.sh`.

Dataset: ANN-Benchmarks SIFT1M, 1,000,000 × 128 base, 10,000 official
queries, L2, K=30, nprobe=64; index SHA-256
`ffa697ed0a3668f563ec99e651c9ab54202aa6e58f34deaeac97a519445403ec`.

| Queries | Threads | PDX ms | Gathered GEMM ms | Faster | PDX Recall@30 | GEMM Recall@30 |
|---:|---:|---:|---:|---|---:|---:|
| 64 | 1 | 18.61 | 103.57 | PDX 5.57× | .95990 | .95990 |
| 64 | 4 | 5.00 | 26.27 | PDX 5.25× | .95990 | .95990 |
| 64 | 8 | 4.85 | 14.34 | PDX 2.96× | .95990 | .96042 |
| 4,096 | 1 | 1,151.67 | 680.54 | GEMM 1.69× | .95234 | .95303 |
| 4,096 | 4 | 320.81 | 202.20 | GEMM 1.59× | .95234 | .95304 |
| 4,096 | 8 | 182.71 | 135.49 | GEMM 1.35× | .95234 | .95303 |

At 4,096 queries / 8 threads, independent-process lifetime peak RSS was
1.761 GB for PDX and 2.294 GB for gathered GEMM (+.533 GB, +30.3%). At 64
queries / 8 threads it was 1.691 vs 2.211 GB. These RSS values include index
loading and file-backed mapped base pages; they do **not** prove a .533 GB
increase in allocated pressure RAM or establish a bounded-execution budget.
The code's estimated GEMM worker scratch is ≤804,608 bytes per worker for
this index (tile plus largest cluster), plus Top-K state; that estimate does
not account for all process allocations or mapped resident pages. The pilot
uses one fixed path ordering, one dataset, one index, and no Faiss, high-D,
I/O, p95, or true hard-budget admission measurement.

The previous serial gate (`C15_FINAL_VERDICT.md`) measured list-major fan-in
65.54 queries/list versus only 1.69 queries/list when preserving probe-rank
waves. This is a real trade-off between reuse and progressive per-query
pruning, but this pilot implements **neither** a new scheduling mechanism nor
an improvement over an established batch baseline.

## Prior-art overlap / what is left

| Proposed engine component | Closest established work | Consequence |
|---|---|---|
| Group queries by IVF list and score batches | Faiss `contrib/big_batch_search.py` supports IVFFlat/PQ/SQ, list-major batches, KNN kernel, threaded prefetch/compute, and checkpoints. [Faiss source](https://github.com/facebookresearch/faiss/blob/main/contrib/big_batch_search.py) | Not an original algorithm; Faiss already tracks query, assignment, and result memory. Its default KNN route is not the optional full pairwise-distance route with a blockwise TODO. |
| IVF Top-K join with blocked GEMM and bounded Top-K | Databricks `NEAREST BY` describes IVF probe joins, fused blocked GEMM, streaming bounded score tiles, and per-query O(K) selection. [Databricks design](https://www.databricks.com/blog/nearest-join-scaling-vector-search-databricks-runtime) | General “memory-bounded batch join” framing is too broad to be a differentiator. Their distributed system is not identical to a standalone C++ engine, but reimplementation alone is not a thesis contribution. |
| Ready-query, partition-major scheduling while preserving stopping decisions | SieveIVF continuous batching and lookahead in Lance. [SieveIVF paper](https://arxiv.org/html/2608.03199v1) | Not an exact duplicate: its stopping condition is an application threshold, not ordinary kth-distance Top-K pruning. It nevertheless covers the generic scheduler pattern; a Top-K-specific improvement needs direct comparative evidence. |
| PDX partial-distance pruning mixed with batched dense work | SuperKMeans combines partial-dimension GEMM and PDX/ADSampling pruning with an adaptive cutoff for Top-1 centroid assignment. [SuperKMeans paper](https://arxiv.org/html/2603.20009v1) | Top-K IVF differs, but “switch GEMM/pruning by batch” is not independently novel. |

## The memory claim is harder than the name suggests

In pinned PDX `f6a26df`, `MmapFile` in `include/pdx/utils.hpp:12–23` actually
allocates a whole-file `char[]` and reads the serialized index; `Restore` then
constructs resident cluster copies (`indexes/ivf_vanilla.hpp:254–274`,
`indexes/ivf_core.hpp:147–195`). Thus the observed loading peak cannot be
controlled by merely tiling GEMM. The existing `IClusterSource` and
`LoadPDXIndexFromStream` path support external F32 cluster data without a PDX
storage rewrite (`indexes/ivf_core.hpp:20–28`,
`indexes/ivf_tree.hpp:1490–1553`), but still retain an O(N) row-location map
of 8 bytes per dense ID (`indexes/ivf_utils.hpp:185–188,242–251`). Some
cursor scratch uses raw `new[]`, outside the custom large-buffer allocator
(`ivf_searcher.hpp:1222,1252–1262,1294–1300`).

Therefore a **strict total-process budget B** would need to account for the
resident index, row map, pruner, loading transients, cluster cache and
simultaneous acquisitions, all workers, route assignments, score/heap tiles,
query input, output, and library/allocator overhead. The present gate caps
only its GEMM tile shape. Calling it “memory-bounded” without qualifying
*which* memory would be misleading.

## Stop decision and reopening criterion

No further large-data download, PDX production patch, or full engine build is
justified for this proposal. A **new** C15 thesis proposal could be opened
only after stating a mechanism with a precise difference from Faiss,
Databricks and SieveIVF, then demonstrating, at matched recall and total
resource cost, a reproducible net improvement on at least two independent
real datasets against fair multicore baselines. The proposal must include a
feasible whole-process memory contract, not only a score-tile bound. The
current pilot satisfies none of those final gates.

The attempted high-dimensional GIST archive was not used in any measurement;
its newly downloaded isolated copy was removed after the novelty gate failed.

No C17, PDX, or C13 production files were modified. `src/c15_parallel_gate.cpp`
and the CMake target are isolated pilot artifacts; a thread-loop capture was
corrected to capture worker ID by value before running the results above.
