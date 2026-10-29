> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# Cross-source candidate-cost characterization: no mechanism yet

**2026-10-26; preregistered protocol:** BUDGET_TRACE_CROSS_SOURCE_PROTOCOL.md, commit `bea1ca5`, before baseline eligibility and diagnostic results. **Verdict:** both added sources passed strict baseline/output correctness, but the combined traces do **not** establish a cheap, reliable continuation rule. Stop before fitting a policy or modifying the production Writer.

## Scope and validation

Two fixed, previously used development sources were added to the TPC-H development traces: 262,144-row, four-rowgroup NYC TLC Yellow Taxi (six numeric/categorical columns) and 120,000-row, two-rowgroup AG News (long text plus label). Both exact CSV/schema hashes matched the prior input manifests. Pristine upstream Release encoded each case and passed the stricter validator for **every logical cell and NULL flag**; the validator rejected a deliberately changed first cell in each (`raw/budget_cross_eligibility.csv`, `raw/budget_cross_*_{baseline_verify,sensitivity}.txt`). This avoids relying on the legacy comparator described in the erratum.

Diagnostic-only FastLanes commit `c2cf6c7` then completed three fresh-process 1/3/7/all-vector candidate traces per case. Every diagnostic artifact passed strict logical verification and had the **same total stored bytes and footer SHA-256** as its pristine baseline: TLC 1,031,512 bytes, AG News 15,555,509 bytes. TLC data SHA-256 was baseline-identical in all three runs; AG News data SHA varied, as in prior baseline observations, so cross-run byte determinism is not claimed. Final seven-vector selection was not changed. Exact writer/validator outputs, checksums and trace counts are in `raw/budget_cross_runs.csv` and `raw/budget_trace_{tlc_yellow_262144,ag_news_train}_rep{0,1,2}.log`.

## Candidate-level observations

Sizes and candidate identities were identical across the three repetitions of each case. Repetition reduces timing noise but does **not** triple the independent decision count. TLC's 24 decisions are four rowgroups of the same six columns, not 24 different sources. All-vector `TryExpr` size is a **candidate payload proxy**, not counterfactual final-file size.

| Development table | Decisions / candidate trials per stage | 1-vector winner = 7-vector | 3-vector winner = 7-vector | 7-vector winner = all-vector | Worst all-vector payload regret from 1 / 3 vectors | Summed all-vector proxy change from 1 / 3 vs 7-vector choice |
|---|---:|---:|---:|---:|---:|---:|
| TPC-H `lineitem` | 16 / 184 | 12/16 | 13/16 | 16/16 | +14.61% / +4.45% | +1.77% / +0.77% |
| TPC-H `part` | 9 / 118 | 9/9 | 9/9 | 9/9 | 0% / 0% | 0% / 0% |
| NYC TLC | 24 / 256 | 16/24 | 22/24 | **22/24** | +14.18% / +1.19% | +3.57% / +0.007% |
| AG News | 4 / 48 | 2/4 | 3/4 | 4/4 | +3.12% / +1.61% | +2.43% / +0.73% |

The **six** three-vector disagreements with the seven-vector choice include three `lineitem` integer columns (each 4.26–4.45% all-vector payload regret), TLC's string/payment columns (one has a **zero** early best/second margin but 1.19% regret), and AG News' second long-text rowgroup (1.61% regret). In one TLC string rowgroup, the three-vector choice is *better* under the all-vector proxy than the seven-vector choice (seven-vector regret 5.73%); a second TLC rowgroup also has a seven-vector/all-vector winner disagreement. Thus the default Wizard is a baseline, **not a full-data oracle**, and summed proxies can conceal opposing per-rowgroup outcomes. The actual files for these counterfactual choices were not encoded.

Median summed candidate-trial wall per repetition at 1/3/7/all stages was 35/39/56/302 ms for TLC and 335/384/514/2213 ms for AG News. Fixed trial order, fresh re-encoding at every stage, cache effects and varying data types prevent adding/subtracting these numbers to claim a production speedup. The diagnostic writer took ~470–476 ms (TLC) and ~3.63–3.68 s (AG News) because it ran extra trials; one-shot pristine baseline writes took 98 and 706 ms. This is measurement overhead, not an adaptive selector result.

Across all four development tables, a seven-vector winner happened to rank at most third after one or three vectors. **That is a post-observation fact, not a certified safe Top-3 rule.** The early best/second margins of incorrect choices overlap margins of correct choices, including ties. No candidate-local cheap signal with a bounded quality/cost tradeoff was established, and a 1→3→7 design that repeats `TryExpr` without reusing work may spend more CPU than the current seven-vector Wizard. The data support the existence of a decision-cost/quality tradeoff, but not a mechanism that resolves it.

Source-level feasibility check: pinned `src/wizard/wizard.cpp::TryExpr` constructs a fresh `InterpreterState` and physical expression for each candidate, executes the sampled vectors, then calls `Finalize()` before `Size()`. `src/expression/physical_expression.cpp::Finalize` flushes codec-specific dictionary/FSST/frequency state, while `Size` reads persistent segment buffers. Thus a genuinely *incremental* 1→3→7 trial is **not already exposed by the current interface**: retaining partially evaluated expressions, querying an intermediate estimate, and later finalizing them would change state lifetime and potentially RAM use. It should not be assumed to be a small Wizard-only change. The diagnostic trace intentionally rebuilt each stage, so it supplies no evidence that such reuse is safe or cheap.

## Stop decision and thesis implication

Per the locked mechanism gate, **no threshold, learned model, Top-K shortlist or Writer patch is fitted from these traces**. The present result is a reproducible characterization chapter, not the proposed thesis's New Mechanism/Implementation/Evaluation. A future attempt needs a distinct mechanism hypothesis—especially how to reuse or avoid early work, and how to conservatively continue uncertain candidates—frozen before a source-family-disjoint evaluation. It must win on actual complete-file write time while bounding real stored-byte, read and RSS regressions. If no such hypothesis can be stated without post-hoc tuning, this selector route should be No-Go rather than extended with more modes.

Recompute the archived summaries from this directory:

```sh
python3 scripts/budget_trace_analyze.py
python3 scripts/budget_trace_analyze.py --cases tlc_yellow_262144 ag_news_train --output-prefix budget_cross
shasum -a 256 -c MANIFEST.sha256
```

The first command reproduces `raw/budget_trace_*` for TPC-H; the second produces `raw/budget_cross_{decisions.csv,summary.json}`. `scripts/budget_cross_source_run.py` records the fixed collection procedure and input hashes; it requires the pinned local inputs, pristine/diagnostic Release probes and strict verifier. No source data are silently substituted.
