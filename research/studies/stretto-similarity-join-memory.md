> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# Stretto similarity-join memory gate — 2026-10-27

## Verdict

**Confirmed code-path resource pressure, but NO-GO for a backend-only thesis
patch.** The end-to-end workload impact remains unmeasured.
`TextSimilarityBackend.run` constructs N-element integer arrays, an N-element
inverse map, and an N-element Python list of float scores even when only 100
distinct text pairs need scoring. Its caller then builds another N-element
mask over an already materialized candidate-pair DataFrame. The redundancy is
real, but removing one temporary array would be another narrow optimization;
eliminating the full candidate-pair representation requires an operator/dataflow
change whose engineering scope is not yet justified by an end-to-end trace.

## Source path and observed use

- `reasondb/backends/text_embeddings.py:TextSimilarityBackend.run` creates
  `codes1`, `codes2`, `pair_keys`, `inverse`, `similarities`.
- `reasondb/operators/filter/extract_and_match.py` and
  `extract_and_match_image.py` map extracted values to the entire `input_data`,
  call `run(texts1, texts2)`, then create an N-tuple mask.
- `reasondb/interface/default_operator_toolbox.py` includes this backend, and
  the single-operator benchmark scripts construct it.
- A search of the shipped paper-result CSVs found no `ExtractAndMatch` operator
  labels. This does not prove the path never runs, but means these artifacts
  cannot establish its end-to-end importance.

## Reproducible isolated measurement

Run from this clone (with `numpy`, `pandas`, `requests`, `psutil` installed):

```sh
for n in 100000 1000000 2000000 4000000; do
  PYTHONPATH=. .venv/bin/python artifacts/probe_similarity_memory.py --pairs "$n"
done
```

Raw JSONL: `artifacts/similarity_memory_probe.jsonl`. Each size is a fresh
process. The probe invokes the **actual backend method** but stubs HTTP to
return a constant score; it measures client-side materialization, **not**
embedding inference, real query latency, or a whole Stretto query. Input pairs
cycle through 100 unique combinations to expose redundant pair materialization.

| Candidate pairs | Distinct pairs sent | RSS after input lists | Peak process RSS | Backend elapsed |
|---:|---:|---:|---:|---:|
| 0.1M | 100 | 85.7 MB | 93.8 MB | 0.015 s |
| 1M | 100 | 103.9 MB | 192.6 MB | 0.135 s |
| 2M | 100 | 118.8 MB | 297.5 MB | 0.280 s |
| 4M | 100 | 153.0 MB | 514.1 MB | 0.568 s |

This confirms roughly linear client memory pressure despite only 100 distinct
server-side similarity computations. It does **not** prove that a new backend
algorithm can avoid the bulk of the real system's peak memory, because the
operator already owns N candidate rows and materializes N output tuples.

## Stop condition and possible larger system question

Do not add a chunk-size knob to `TextSimilarityBackend` and call it a thesis.
The only potentially broad question is whether Stretto can defer or avoid
candidate-pair materialization across semantic joins while preserving result
semantics and bounded memory. Before code, capture a real end-to-end profile
showing the operator is selected in at least two independent workloads and
that candidate-pair materialization dominates peak RSS or failed queries.
Then estimate whether a factorized/batched operator can be added through a
small interface boundary rather than a query-engine rewrite. Otherwise retain
this as a documented bottleneck and choose another project center.
