# Compact aggregate Spill: final bounded research verdict (2026-10-25)

> Curated public copy. Detailed subordinate logs and local plans were not republished; their local links have been rendered as plain titles.

## Final bounded answer

At the pinned DuckDB source snapshot `e8681bb4474d9d9d38e2ecf595d4dd1f1366939b`,
this work identifies a real but narrow limitation: for supported fixed-width,
pointer-free high-cardinality `COUNT`/`SUM` states, native external aggregation can
consume enough temporary storage that several concurrent queries exhaust a shared
temporary filesystem even when the machine has sufficient RAM to keep running.

Mode 9 demonstrates a useful conditional remedy. By externalizing those eligible
states more compactly, it reduced temporary-storage pressure enough to turn many
`ENOSPC` failures into successful queries. The strongest result is four concurrent
32M-row queries under a shared 2 GiB RAM cgroup and shared 2 GiB ext4 temporary
filesystem: Mode 9 completed 20/20 queries for both `COUNT` and `SUM`, while native
completed 8/20 and 3/20 respectively. This is a genuine **temporary-quota completion
benefit**.

It is not, however, a demonstrated general memory or throughput optimization. Mode 9
can add allocation and CPU work; at a 1 GiB hard-RAM cap it still incurred one cgroup
OOM kill in each query class. When disk was sufficient or concurrency was lower, its
completion advantage disappeared and it could be slower. The experiments do not show
a lower intrinsic RAM requirement, universally lower process RSS, or higher sustained
service goodput.

The stricter objective proposed for the next stage—make compact aggregate state an
actual-spill-only native physical format, selected before the first native-wide write,
with a bounded parallel lifecycle—was **not implemented**. Fresh tracing confirms that
the current `external_on` signal fires and Mode 9 starts conversion even in controls
that write zero spill bytes. A non-destructive scheduler probe showed that four parallel
sink tasks can be parked and resumed, but independent review found that it has no
all-source census or bootstrap reservation and publishes `COMMITTED` during the tested
cancellation path. It is therefore unsafe to attach destructive drain or representation
commitment to that bridge.

This bounded effort stops at G001 with a negative engineering decision: do not proceed
to G002/G003 on the current trigger and probe. This does not prove that every possible
conditional design is impossible; conditional A remains conceptually open to a future,
separately designed all-source protocol. It does establish that neither the strict
native-format objective nor a safe conditional candidate was produced in this effort.

## Evidence summary

The historical Linux gate used one cgroup for all four query processes, swap disabled,
four DuckDB threads per query, and a shared physical ext4 temporary filesystem. These
are submitted-query completion counts, not successful-query latency or steady-state
throughput measurements.

| Resource envelope / evidence | Native | Experimental result | What it establishes |
|---|---:|---:|---|
| 2 GiB RAM / 2 GiB temp, 4 concurrent 32M `COUNT`, 5 batches | 8/20 | Mode 9 **20/20** | Conditional shared-temp-quota rescue; native's other 12 queries failed with `ENOSPC`; no Mode 9 OOM observed. |
| 2 GiB RAM / 2 GiB temp, 4 concurrent 32M `SUM`, 5 batches | 3/20 | Mode 9 **20/20** | Same conditional rescue; native's other 17 queries failed with `ENOSPC`; no Mode 9 OOM observed. |
| 1 GiB RAM / 2 GiB temp, 4 concurrent 32M `COUNT` | 13/20 | Mode 9 **19/20** | More completions, but Mode 9 still had **1 cgroup OOM kill**; not a zero-OOM envelope. |
| 1 GiB RAM / 2 GiB temp, 4 concurrent 32M `SUM` | 3/20 | Mode 9 **19/20** | More completions, but Mode 9 still had **1 cgroup OOM kill**; not a lower hard-RAM proof. |
| 4 GiB configured no-spill control, 128M `COUNT` | Native allocation baseline | Mode 14 **+37% cumulative allocation** | Eager conversion imposes material work even when no physical spill occurs. |
| 4 GiB configured no-spill control, 128M `SUM` | Native allocation baseline | Mode 14 **+28% cumulative allocation** | Same no-spill tax; small timing differences do not support a speedup claim. |
| Fresh macOS trace, forced-spill `COUNT` | Native 257,097,728 spill bytes | Mode 9 85,721,088 bytes | Descriptive single observation: −66.7%; not a repeated performance gate or hard-RAM test. |
| Fresh macOS trace, forced-spill `SUM` | Native 306,774,016 spill bytes | Mode 9 120,553,472 bytes | Descriptive single observation: −60.7%; same limitation. |
| Fresh macOS trace, all 8 native/Mode 9 cells | 8/8 processes exited 0 | Every native/Mode 9 result pair matched | Correctness for the traced scalar queries; does not prove the transition lifecycle. |
| Archived 4-thread freeze probe | — | 3 waiters blocked/resumed in each COUNT/SUM run | Proves only the scheduler bridge; not an all-source or failure-atomic commit. |

Full evidence and scope are in the
hard shared-resource gate and the
Mode 14 pinned-partition gate.
Fresh trace evidence is in the
current-trace synthesis,
and the reviewed scheduler experiment is in the
archived freeze-probe report.

### Do not conflate three different outcomes

1. **Single-query or batch completion** asks whether submitted work finishes inside a
   stated RAM and disk envelope. Mode 9 has strong positive evidence here when shared
   temporary disk is the binding resource.
2. **Concurrency capacity** asks how many queries can coexist at an acceptable failure
   and latency rate. The four-query batches show a conditional capacity improvement
   under the tested 2 GiB/2 GiB envelope, but do not establish a general concurrency
   limit across workloads or resource scales.
3. **Sustained service goodput** asks how many successful queries per second a system
   can maintain under a controlled arrival or closed-loop protocol, including failure
   rate, latency percentiles, queue growth, and cleanup. No such endpoint was completed.
   Finite batches in which native queries fail quickly cannot be re-labelled as a
   general throughput comparison.

Accordingly, the primary supported metric is **whole-batch completion under a specified
hard shared RAM cap and shared temporary-disk capacity**. Temp occupancy, OOM events,
successful-query latency, cumulative allocation, and sampled memory categories are
guardrails. Peak RAM reduction and sustained queries/second remain unproven.

## What the prototypes do—and cost

Mode 9 avoids some native-wide temporary representation for eligible fixed-width
aggregate states by using a narrower pointer-free representation and later rebuilding
native aggregation state. Its benefit is less temporary-file demand and reduced
write/cache pressure in the tested quota-bound cases. Its costs include conversion,
serialization, reconstruction, additional allocations and CPU work. The memory
diagnostic in the hard-resource report sampled higher anonymous cgroup memory for Mode
9 than native in one comparable batch, while sampled file-cache maxima were lower;
those maxima were not simultaneous and cannot be summed. Therefore the most defensible
description is: **extra compute and allocation are traded for lower temporary-storage
pressure**, without a proven universal direction for peak RSS.

Mode 14 repaired one lifetime defect by retaining source append pins during direct
partition conversion, and it reduced sampled RSS in several macOS runs. But it remains
a conversion pipeline, releases sources only partition-at-a-time, allows overlapping
exporters without a global physical-memory budget, and finally reconstructs native
hash-table state. The 16 MB configured-memory stress result reached roughly 2.18 GiB
process RSS, illustrating that DuckDB's `memory_limit` is not a process hard-RAM bound.
Mode 14 is therefore neither the proposed block-bounded mechanism nor a native compact
Spill format.

## G001 final evidence and bounded stop

The initial source audit recorded a NO-GO for the strict actual-spill-only transition;
its detailed reasoning is in
G001_TRANSITION_FEASIBILITY.md.
Fresh trace and probe work then tested the two open questions rather than relying only
on that audit.

### Current trigger fails the no-spill contract

The fresh macOS trace ran `forced_spill` and `no_spill_control` × `COUNT`/`SUM` ×
native/Mode 9 in eight fresh processes. All exited 0 and every paired result matched.
In forced-spill observations, `external_on` occurred before the first recorded write,
and Mode 9 descriptively reduced reported spill bytes by 66.7% for `COUNT` and 60.7%
for `SUM`. These are single diagnostic observations, not repeated performance results.

Crucially, `external_on` also fired in both 4 GiB controls that wrote zero spill bytes,
and Mode 9 emitted `export_begin` in those controls. The current Option A trigger thus
fails the required zero-conversion no-spill fast path. It predicts external pressure;
it does not establish that physical spill will occur. The actual eviction hook remains
too late and too generic: it sees a buffer and memory tag, not an aggregate-schema-aware
pre-write representation handoff.

### Scheduler bridge works narrowly but is unsafe for commitment

The minimal opt-in freeze probe confirmed a useful fact that the initial audit had not
settled: the outer interrupt/callback path and `PipelineExecutor` `BLOCKED` propagation
can park parallel `PhysicalHashAggregate::Sink` work before consuming retained chunks
and later resume it. Four-thread `COUNT` and `SUM` each reached `max_active=4`, blocked
and resumed three waiters, and produced matching scalar fingerprints. A failpoint also
returned through `NATIVE_ONLY` with 3/3 waiters resumed.

Independent code review nevertheless raised **HIGH-severity** transition-safety issues
and rejected destructive use:

1. the probe has no registry or epoch-validated census of every local source and cannot
   prove that late sink/combine tasks participate in one representation decision;
2. it obtains no progress-safe compact-output bootstrap or physical workset reservation;
3. the SIGINT case emitted `COMMITTED`, attempted one wake, exited 1, and recorded
   `resumed=0`, so cancellation semantics are incorrect;
4. callback propagation from an RAII destructor was not shown noexcept-safe during
   unwinding; and
5. blocked `Combine`, admitted-call exceptions, reusable-state reset, destructive
   export, ownership transfer and representation publication were not tested.

The archived trace word `COMMITTED` means only that the probe's admitted-call counter
reached zero. It does not mean that aggregate sources, memory, or a spill representation
were committed. The exact probe patch and evidence were archived, and the probe was
removed from the live source after review.

### Decision for this bounded effort

Following the approved
research plan and
validation specification, the
G001 stop gate is met negatively. **Do not build destructive block drain or compact
commitment on the current `external_on` trigger or archived freeze probe.** No G002
exclusive-drain source implementation and no G003 global-admission/bounded-import source
implementation were made. This is a final result for the bounded effort, not proof
that every future conditional architecture is impossible.

## Fresh-validation boundary

No new compact physical-format candidate exists, so there is no fresh candidate binary
to benchmark under hard resources. The eight fresh macOS traces validate the recorded
answers and event order only. A read-only Docker diagnostic on 2026-10-25 also found the
Docker Desktop daemon unavailable. Consequently:

- the Linux 2 GiB/2 GiB and 1 GiB/2 GiB numbers above are historical evidence for the
  already-built Mode 9 binary at the pinned snapshot;
- they are not presented as validation of a new candidate;
- macOS `memory_limit` or sampled process RSS is not substituted for a Linux cgroup
  hard-memory test; and
- no claim is made that the reviewed conditional probe is a candidate, that a new
  hard-resource envelope was found, or that sustained goodput improved.

## What a separate future conditional design would require

Conditional A remains conceptually open only as a new, separately reviewed design. It
must not reuse the probe's counter as a commit protocol or add another admission
threshold. Before destructive drain work, it would need all of the following:

1. **Operator-owned pre-write decision/handoff:** a point before native
   materialization/write carrying aggregate schema, eligibility, source identity and
   representation ownership. The strict physical-format path requires an irrevocable
   actual-spill decision; a conditional path needs a distinct admission signal that
   empirically preserves the zero-conversion no-spill fast path.
2. **Scheduler-safe global transition:** a callback-capable operator coordinator that
   can close registration, quiesce all sink/combine producers, freeze a complete source
   census, allocate a minimum progress bootstrap, and atomically commit every worker to
   either native or compact representation without blocking the worker pool.
3. **Physical workset credits:** accounting and admission for already-resident sources,
   per-task scratch/output, compact destination, reconstruction resize peaks, and
   retained finalized output; logical reservations alone are insufficient.
4. **Bounded post-commit dataflow:** block-last-use release, bounded output fan-out,
   bounded replay/import, exact cancellation and exception cleanup, and no native
   fallback after destructive compact commitment.
5. **A true no-spill fast path:** zero compact rows/bytes and no material allocation,
   RSS or latency regression when no physical spill is required.
6. **Fresh hard-resource and service validation:** rebuild native and all baselines from
   one source snapshot; repeat shared cgroup/shared-filesystem rescue and counterexample
   cells, then measure sustained goodput with failure and latency accounting.

The strict native physical-format objective still requires the pre-write operator
contract above. A future conditional branch may explicitly relax actual-spill-only
selection, but it must still establish an all-source, failure-atomic coordinator and
pass zero-conversion no-spill plus joint hard-resource gates. Neither more threshold
tuning nor an isolated pin-transfer patch is warranted on the current path.

## Thesis-safe contribution and novelty boundary

This work is suitable for a doctoral proposal or thesis chapter when stated as:

- a resource-accounting study of high-cardinality parallel aggregation;
- evidence that aggregate-state-aware compact externalization can improve query
  completion under a hard shared temporary-storage constraint;
- a bounded negative feasibility result: the inspected strict actual-spill-only signals
  are insufficient, the current Option A trigger violates the no-spill fast path, and
  the tested scheduler bridge lacks safe all-source/failure-atomic commitment; and
- a reproducible framework that separates query completion, RAM safety, disk pressure,
  concurrency capacity, and sustained service goodput.

It is **not** currently defensible to claim a completed novel production optimization,
a general memory-aware parallel aggregation solution, a native compact-only Spill
format, proof that all possible conditional designs are impossible, or novelty relative
to the latest DuckDB upstream. The source conclusions are limited to the pinned
`e8681bb` snapshot; a latest-upstream novelty claim would require a new upstream source
and literature audit.

## Final bounded verdict

**Useful conditional Mode 9 prototype, No-Merge; current strict and conditional
transition mechanisms are a bounded negative result.** Mode 9 solves an observed
temporary-disk-quota failure mode for the tested eligible `COUNT`/`SUM` workloads and
can raise completion capacity when shared disk is the bottleneck and adequate RAM
headroom exists. It does not solve general peak-RAM, allocation, latency, or throughput
optimization. The fresh trace rejects `external_on` as a no-spill-safe trigger. The
freeze probe proves only that parallel tasks can be parked and resumed; its missing
source census/bootstrap and incorrect cancellation state make destructive use unsafe.
The bounded project therefore stops at G001 without G002/G003 implementation. A future
conditional architecture remains conceptually possible, but requires a separate design
and cannot be claimed as an outcome of this work.
