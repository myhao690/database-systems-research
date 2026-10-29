> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# C15 final bounded verdict — 2026-10-27

## Decision

**NO-GO for committing the proposed adaptive PDX-pruning/GEMM switch as an
independent MSc thesis core or starting a production patch.** The measured
batch-size crossover is a real engineering observation on one dataset, but the
broad mechanism is substantially covered by published code and the remaining
Top-K-specific scheduling idea is neither implemented nor shown to yield net
benefit. This is a verdict about this proposal, not proof that all C15 vector
similarity-join research is exhausted.

## Evidence that an execution trade-off exists

The isolated C++ gate in `src/c15_gate.cpp` used the same pinned PDX IVF-F32
index and the same top-`nprobe` centroid-ranked clusters for both paths on
ANN-Benchmarks SIFT1M (1,000,000 × 128, K=30). It included routing, grouping,
candidate gathering, scoring and Top-K merge. At 64 queries / 64 probes,
serial per-query PDX took 18.08 ms versus 75.06 ms for gathered cluster GEMM.
At 4,096 queries / 64 probes the order reversed: PDX 1,180.41 ms versus
gathered GEMM 615.67 ms (1.92× faster). Recall@30 was 0.9523/0.9530 and
Top-K set agreement was 0.9989 at the latter point. An independent spot rerun
confirmed the large- and small-batch direction, not the exact crossover point.
Raw numbers and commands are in `results/`, `raw/`, `C15_EMPIRICAL_GATE.md`,
and `REPRODUCE.sh`.

The all-at-once cluster group has 65.54 queries per active cluster on average
at 4,096 queries / 64 probes. Grouping only queries at the same probe rank
falls to 1.69. This shows a **potential scheduling conflict**: retain
per-query threshold progression or expose large matrix batches. It does not
demonstrate that an intermediate schedule is useful.

The gathered route touches row-major base vectors as well as the PDX index.
In process-isolated runs it increased peak RSS from 1.695 to 2.282 GB, but
macOS peak memory footprint only from 1.688 to 1.763 GB (+4.5%); file-backed
pages must not be equated with additional allocated RAM. Persistently packing
all clusters raised peak footprint to 2.315 GB (+37.1%) and has an unmeasured
maintenance cost. The 2.22× speedup of that path is not a free systems gain.

## Why this is not our independent mechanism

- [PDX pinned `f6a26df`](https://github.com/cwida/PDX/blob/f6a26df53c143dbe64b1e6c1ba22d8f1de931f7b/include/pdx/indexes/ivf_vanilla.hpp#L34-L41)
  already has a Flat `BulkSearch` but IVF inherits a throwing stub. Filling
  the stub with batched search is useful engineering, not automatically
  research novelty. Its [IVF loop](https://github.com/cwida/PDX/blob/f6a26df53c143dbe64b1e6c1ba22d8f1de931f7b/include/pdx/ivf_searcher.hpp#L447-L612)
  already transitions from dense-prefix work to sparse survivor positions
  within a query.
- [SuperKMeans (Kuffo, Hepkema, Boncz, 2026)](https://arxiv.org/html/2603.20009v1)
  already interleaves partial GEMM with PDX/ADSampling pruning and adapts the
  partial dimension cutoff to observed pruning. Its task is Top-1 centroid
  assignment, not an IVF Top-K join; that difference is an implementation and
  research question, but the broad hybrid idea belongs to this prior work.
- [CABANA (2025)](https://caslab-yonsei.github.io/publications/cal25-mkim/)
  groups IVF queries by cluster and turns fine search into GEMM.
  [Databricks NEAREST BY (2026)](https://www.databricks.com/blog/nearest-join-scaling-vector-search-databricks-runtime)
  already implements an IVF Top-K join with cluster-local GEMM and bounded
  per-query Top-K state. No claim here assumes their unpublished code can be
  directly benchmarked on this machine.

Consequently, neither a global small/large-batch selector nor a simple
SuperKMeans Top-1-to-Top-K adaptation would meet the requested independent
systems-contribution standard.

## Evidence still absent

Only SIFT1M/L2/128D and a serial outer loop were run. There is no second
independent dataset, high-dimensional embedding workload, fair parallel PDX
comparison, Faiss/CABANA-style multicore baseline, measured PDX survivor
profile, randomized run order, p95, or implemented scheduler. The reproduced
crossover is therefore **not** a proof of broad gains. `REPRODUCE.sh` relies
on external files and a prebuilt index; see the empirical report for scope.

## Stop rule and possible reopening

Stop this proposal now rather than adding thresholds or a partial production
patch. Reopen only if a distinct Top-K-specific mechanism can be stated against
the three prior-art baselines above **and** a new bounded experiment shows
that it preserves query-threshold pruning while obtaining cluster reuse, with
net gains at matched recall on at least two independent datasets under fair
parallel and memory accounting. A crossover between two already known
strategies alone does not satisfy that gate.

C17, the pinned PDX checkout, and previous C13 artifacts were not modified.
