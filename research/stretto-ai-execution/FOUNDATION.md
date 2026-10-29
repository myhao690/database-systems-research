> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# Project foundation: Safe and Recoverable Reuse of AI Operator Work

**Status (2026-10-28): engineering foundation ready; MSc thesis conditional.**
Isolated branch `research/ai-execution-foundation`, base Stretto commit
`6a540eab0581fa7e4b2605421839bfc3dde77eae`. The C17 repository is not
part of this project and was not edited. This branch combines two independently
developed, still-unsubmitted engineering patches; it is **not** an upstream PR
or a demonstrated thesis contribution.

Follow-up evidence and the local hardware/data limit are recorded in
`research/LOCAL_FEASIBILITY_GATE.md`. A local real-model **component** probe
worked, but no real Stretto precompute trace or KV-server run was available.

## One-sentence objective

Make reused AI-operator answers in an analytical query engine refer to the
**same effective input and model request**, and make completed expensive work
recoverable after an interrupted run, while quantifying the cost of those
guarantees against the simplest correct alternatives.

This is a *systems integration and measurement* project, not a claim to invent
caching, write-ahead logging, or batching. Its relevance to Systems for AI is
that incorrect reuse changes query answers, while lost recordings can repeat
expensive model work. A thesis must establish these effects in realistic
workloads, not merely demonstrate isolated unit tests.

## Why this project, and what is already solved

Stretto already has within-operator pair deduplication (`reasondb/backends/
text_qa.py`), completed-response caches (`reasondb/reasoning/llm.py`), whole-
operator precompute markers (`reasondb/executor.py`), preparation memoization,
and memory-budgeted KV batches. Its [paper](https://arxiv.org/abs/2602.04430)
describes KV reuse. [LOTUS](https://lotus-ai.readthedocs.io/en/latest/configurations.html)
provides persistent semantic-operation caching;
[SGLang](https://arxiv.org/abs/2312.07104v2),
[BatchLLM](https://arxiv.org/abs/2412.03594v3), and
[Sema](https://arxiv.org/abs/2603.11622v1) cover important cache-aware
scheduling and semantic batching ideas. **Generic cross-query caching or
batching is not our proposed novelty.**

The concrete local findings are narrower but real:

1. The original LLM/embedding cache identity omitted request components.
   The separate cache-safety worktree reproduces wrong-model reuse, stale
   image-byte reuse and wrong input-limit reuse; its isolated patch adds
   versioned identity, atomic cache writes and instance-local singleflight.
   See `research/CACHE_SAFETY_REPORT.md` for baseline-red and test evidence.
2. Original precompute saved the entire growing JSON after every query with
   `open(..., "w")`. Injected failure truncated a valid recording to one byte.
   The replay worktree's delta + atomic-final-export patch preserves committed
   query responses across tested process failures. See
   `research/REPLAY_CHECKPOINT_FEASIBILITY.md`.
3. **Unresolved cross-layer boundary:** `SimulateStore.record_vision` and
   `lookup_vision` key a recording by model ID, question and **path string**.
   Replacing bytes at that path still returns the old answer; run
   `PYTHONPATH=. .venv/bin/python research/probe_replay_identity.py` to
   reproduce. This is a limitation under mutable data, **not proof of a bug
   under Stretto's static benchmark snapshot contract**. Whether mutable
   inputs are in scope must be decided explicitly before changing the format.

## Existing code foundation and verification

The branch applies both isolated patches without file conflicts. Cache code:
`reasondb/reasoning/{llm,embeddings}.py`, `reasondb/utils/cache.py`.
Recording/recovery code: `reasondb/backends/simulate_store.py`,
`reasondb/evaluation/precompute.py`, monitor telemetry and related scripts.
Targeted integration verification: **70 tests passed** across the new
regression suites and existing replay/merge/invalidation/telemetry tests;
Ruff checks, JavaScript syntax checks and `git diff --check` passed.
No paid API call, GPU workload, full-suite pass, Python 3.12 run, or upstream
maintainer review has occurred. The linked venv is Python 3.13 and lacks
`torch`/`tqdm`; dependent suites cannot currently collect. The integrated
branch is a research base, not production-ready.

Recordings benchmark (real text columns, synthetic distinct questions, no
inference): at ten growing queries, incremental checkpoints plus final export
were 2.5–2.7× faster and wrote about 64% fewer bytes than full atomic rewrites.
But a stronger dirty-guard baseline **wins** when only 2/10 queries add data
(0.038 s versus 0.051 s for deltas). At 5/10 it loses (0.184 s versus
0.123 s). These are checkpoint-only results, not end-to-end speedups. Raw
data: `research/interleaved_postfix.jsonl` and
`research/dirty_guard_matrix.jsonl`.

## Thesis research question and bounded scope

> Under realistic repeated and interrupted AI-query workloads, which request
> identity and recording lifecycle guarantees are needed for correct reuse,
> and can they be implemented with bounded CPU/RAM/I/O overhead relative to
> simple cache invalidation and atomic full snapshots?

Three linked dimensions, **one system problem**:

- **Identity:** effective request includes model/version policy, prompt,
  modality input content or a valid immutable snapshot token, and relevant
  execution parameters. Establish what Stretto can know; do not silently
  promise detection of model aliases changing behind a stable ID.
- **Recovery:** define a completed-work commit boundary and restart behavior.
  The current delta prototype covers process crashes between queries; power
  loss, distributed writers and exactly-once external model calls are not yet
  supported and must not be claimed.
- **Cost:** distinguish safety overhead on unique requests from savings on
  repeated/interrupted work. Use independent `perf_counter` wall-clock
  measurement: `SimulatedClock` credits historical runtime on replay, so
  existing phase times are not always observed wall time.

The thesis does **not** need a new cache replacement algorithm. A credible
contribution would be a verified cross-layer contract, a small reliable
implementation, and a workload study showing where the contract matters and
where its cost is unwarranted. The exact mechanism beyond the two existing
patches is selected only after trace evidence.

## Decisive experiment before more core code

Collect two independent Stretto workloads (e.g. review/text and image or
email/text) with repeated queries, distinct queries, and controlled
interruption. Capture raw trace events and verify their provenance. For each
query, measure: actual monotonic wall time; model-request identity and count;
cache hit/miss; newly committed response count; persistence bytes/time;
peak RSS; result correctness; completed model calls redone after restart.
Use a real model server for performance claims. A deterministic fake model is
valid for correctness and fault-injection tests only. Do not sum overlapping
per-thread timers into a critical path.

`research/audit_precompute_trace.py` is a dependency-free first-pass monitor
JSONL summarizer: it groups interleaved jobs, counts active versus cached
precompute queries, and separates delta/full write counts, bytes and time.
Its tests include a trace generated by the actual `run_precompute` + monitor
path. It deliberately **does not** turn event timestamps or `SimulatedClock`
phase values into observed wall time. Once real traces are available, run
`PYTHONPATH=. .venv/bin/python research/audit_precompute_trace.py <trace.jsonl>`.

Compare, under the **same request semantics and data**:

| Baseline | Purpose |
|---|---|
| Upstream Stretto | Detect actual faults and raw overhead |
| Safe identity only | Isolate correctness and keying overhead |
| Atomic full save + dirty guard | Strong simple recovery/performance competitor |
| Delta recording only | Isolate I/O and recovery cost |
| Integrated candidate | Test whether combined guarantees have net value |

Run cold/warm caches, unique/repeated inputs, mutable path content, and process
kill at before/after publication boundaries. Report p50/p95 per-query wall
latency, total elapsed, API/model-call count and redo, wrong/stale hits,
write volume, final/load time, CPU and peak RSS. Keep correctness and
performance results separate.

## Go/No-Go rules and project deliverables

**Continue to a thesis implementation only if** (a) at least two realistic
workloads exhibit a material identity/recovery issue under an explicit data
contract; (b) a baseline comparison shows the integrated mechanism adds
measurable value over atomic full save + dirty guard and safe cache keys;
(c) unique-request p95 and peak RSS regressions remain bounded and explained;
and (d) integration does not require invasive changes to the model server or
query optimizer. Quantitative working targets, not observed results: zero
wrong reuse and zero loss of previously committed responses in fault tests;
<5% unique-request p95 overhead; no unexplained >10% RSS increase; a clear
reduction in expensive redone model work or end-to-end time on **both**
workloads. These thresholds can be revised before data collection, not after
seeing results.

**Stop this thesis route** if static snapshots make identity failures
irrelevant, crashes/repetition are too rare for meaningful benefit, or the
dirty guard captures most actual gains. Keep the independently useful fixes
and start a separate project; do not add cache policies or benchmarks merely
to save this thesis.

Full MSc deliverables would be: (1) workload and failure characterization;
(2) a precise AI-result identity/recovery contract; (3) minimal open-source
implementation and tests; (4) strong-baseline, multi-workload evaluation;
(5) negative results and deployment boundaries; (6) reproducibility package.
This branch currently supplies **the code/test foundation and first negative
boundary**, not deliverables (1), (4), or a complete thesis.

## Immediate next milestone

Obtain real Stretto trace/model access and run the two-workload audit before
further implementation. If that access is unavailable, finish the correctness
artifact and explicitly downgrade the project to an engineering portfolio
piece; model-free timings must not be promoted to a thesis performance claim.
The checked local environment has Ollama only, not the Stretto GPU/KV servers;
the shipped paper CSVs cannot substitute for raw precompute traces. A
controlled partial-query failure also showed that current durability is only
at completed-query granularity; within-query recovery would require a new
request/result data flow and is **not** part of the existing patch.

Minimal local verification:

```sh
.venv/bin/python -m pytest -q tests/test_analyze_paper_phase_mix.py \
  tests/test_audit_precompute_trace.py \
  tests/test_ai_cache_identity.py \
  tests/test_simulate_store_incremental.py tests/test_precompute_query_telemetry.py \
  tests/test_simulate_store_merge.py tests/test_simulate_store_filter_stats.py \
  tests/test_simulate_store_compression.py tests/test_merge_precompute.py \
  tests/test_invalidate_precompute_ops.py
PYTHONPATH=. .venv/bin/python research/probe_replay_identity.py
```
