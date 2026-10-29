> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# C18: Loss-Transparent CSV Auto-Detection — execution gate

**Date:** 2026-10-27. **Verdict for the proposed independent MSc thesis mechanism: NO-GO at this gate.** DuckDB's default CSV autodetection **does** silently lose real records in several public files; this is not a manufactured benchmark. However, its known `skip_rows` issue already has an open upstream patch and proposed resolution, `sniff_csv` exposes the inferred skip count, and the strongest immediate intervention is a small bug fix or warning. We have **not demonstrated** a distinct, bounded mechanism that outperforms these simple baselines on independently held-out data without high false alarms. In accordance with the pre-registered plan, **no C++ patch was started**. C17 was untouched.

This reverses the previous optimistic selection of C18 as our highest-confidence *complete* MSc topic. The observed defect is real; the thesis contribution was overestimated before upstream/prior-art and real-data gates. C18 may still be a CWI-supervised integration/robustness project with access to further datasets and guidance, but **we should not independently commit months to this exact “loss-transparent” mechanism now**.

## 1. Plan executed and stop point

| Gate | Result |
|---|---|
| Upstream and prior-art audit | Completed on DuckDB main `142a9e7dbce75c690ff355cf4218f0ffa31f4190` (2026-10-27), Pollock `bd2a646f4cf55d2bd4e76df511c9c9f675ae7bcc`, DuckDB 2.0.0 executable. Existing overlapping PRs and research found. |
| Public real-data characterization | 100 real CSV + clean targets + loading parameters, 109.2 MB raw inputs; 100/100 default reads returned success, but only 58/100 matched clean **row count and column count**. This is a weak structural proxy, not 42 verified silent-loss defects. |
| Strict loss confirmation | Six default reads returned fewer rows than the annotated clean target while inferred `SkipRows` exceeded the annotated preamble. Manually specified dialect/schema with bounded options recovered **all intended row tuples** in each of six. |
| Competing/simple baselines | `null_padding`/Pollock permissive options, full-file sample, and a `SkipRows>0` warning analyzed. These are inadequate as universal repair, yet the warning is a strong *detection* baseline. |
| C++ mechanism and final performance evaluation | **Not started**, by stop rule: novelty/independent mechanism gate not met. No performance-gain or C++ completion claim. |

## 2. Source and novelty audit

- [CWI C18](https://www.cwi.nl/en/research/database-architectures/general-information-on-msc-projects-at-the-da-group/msc-projects-at-cwi-amsterdam/) asks for self-correcting CSV reader behavior based on binding-time sniffing. The page is project motivation, **not evidence of an unoccupied contribution**.
- [Issue #25827](https://github.com/duckdb/duckdb/issues/25827) remains open and reports exactly the dangerous single-column trailing-delimiter example. Its author already names “retain rows, reject, or warn” as possible resolutions. A related [PR #27335](https://github.com/duckdb/duckdb/pull/27335) was closed **unmerged** and moved to open [duckdb-bot PR #22](https://github.com/duckdb-bot/duckdb/pull/22), head `e78a071df6ae1a3fd3c4580204d80376791f678b`. It prevents one version of the one-column tail case but explicitly does not cover two wider tail rows or general width growth. We must not present its fix as ours.
- In latest main, [`dialect_detection.cpp`](https://github.com/duckdb/duckdb/blob/142a9e7dbce75c690ff355cf4218f0ffa31f4190/src/execution/operator/csv_scanner/sniffer/dialect_detection.cpp#L274-L298) can advance `dirty_notes` on width changes and [assign it to inferred `skip_rows`](https://github.com/duckdb/duckdb/blob/142a9e7dbce75c690ff355cf4218f0ffa31f4190/src/execution/operator/csv_scanner/sniffer/dialect_detection.cpp#L399-L407). Ordinary `read_csv` can therefore succeed without warning while excluding a prefix. But [`sniff_csv` already exposes `SkipRows`](https://github.com/duckdb/duckdb/blob/142a9e7dbce75c690ff355cf4218f0ffa31f4190/src/function/table/sniff_csv.cpp#L69-L106) and its generated prompt includes `skip=`; a wrapper can warn without any new parsing mechanism.
- DuckDB [PR #20005](https://github.com/duckdb/duckdb/pull/20005) already ranks candidates using whether non-strict states were needed; “repair-cost/strictness-aware scoring” alone is not novel. [PR #27630](https://github.com/duckdb/duckdb/pull/27630) has merged a comment/quote candidate fix. Open [PR #27500](https://github.com/duckdb/duckdb/pull/27500), [#27515](https://github.com/duckdb/duckdb/pull/27515), [#26171](https://github.com/duckdb/duckdb/pull/26171) cover other quote/escape/type-conversion classes; their mechanisms differ, so combining them into one vague “loss-awareness” patch would expand scope.
- [CleverCSV](https://github.com/alan-turing-institute/CleverCSV) already uses consistency/tie handling and can abstain; [CSVsniffer](https://github.com/ws-garcia/CSVsniffer) studies structural uniformity and type-based inference; [csv-nose](https://github.com/jqnatividad/csv-nose) exposes preamble and sampling diagnostics. Candidate ranking, “abstain on ambiguity,” and skip diagnostics therefore require a more precise difference and measured benefit before a novelty claim.

**Confirmed missing feature is not identical to a thesis gap.** The public API lacks an uncertainty/record-accounting certificate, but adding a field/warning would be a useful small usability fix, not sufficient independent research. A genuinely better decision would need to distinguish legitimate preambles from discarded data and beat `SkipRows>0` on true table content, with bounded overhead. We have not shown such a method.

## 3. Real-file experiment and correctness checks

Dataset: [Pollock pinned real survey sample](https://github.com/HPI-Information-Systems/Pollock/tree/bd2a646f4cf55d2bd4e76df511c9c9f675ae7bcc/survey_sample): 100 original CSV, 100 cleaned targets, 100 parameter annotations. Files come from a broader [GovUK/Mendeley survey](https://hpi.de/naumann/projects/data-preparation/pollock.html), **but this repository's 100-file subset does not supply a reliable per-file source/publisher grouping**; it cannot by itself certify two independently held-out source populations. The full 3,712-file survey has structural flags, not full target-record truth, and many local `survey/csv` files are Git LFS pointers. The official OwnCloud archives timed out in this environment. We therefore evaluate the 100-file sample as one public corpus, not as two independent held-out corpora.

Method: DuckDB Python `2.0.0`, in-process, default `read_csv` fully consumed via `COUNT(*)`; clean CSV parsed with Python's fixed comma/quote reader. Compare **row count and column count only** for the broad sweep. Each input also receives `sniff_csv` metadata. `null_padding=true` and Pollock-style `null_padding=true, strict_mode=false, ignore_errors=true` are separate tracks; they are **not** DuckDB defaults. More detailed six-case oracle testing uses the Pollock annotated dialect, explicit all-VARCHAR column count, `null_padding=true`, `strict_mode=false`, and compares ordered-cell row tuples as **multisets including duplicate multiplicity**, normalizing only trailing empty cells. This manual configuration is ground-truth control, not an automatic candidate. Raw JSON and scripts are in this directory.

| Outcome on 100 real files | Count | Interpretation |
|---|---:|---|
| Default read returned success | 100 | No exception is not correctness. |
| Row **and** column count equal clean target | 58 | Upper-bound proxy for full correctness; matching counts can hide wrong cells. |
| Count/schema mismatch | 42 | Includes genuine errors, benign/annotation ambiguities and non-rectangular-clean cases; **not** 42 proven bugs. |
| Fewer rows than target | 7 | Six meet strict unexpected-prefix criteria; one has annotated legitimate preamble and is excluded from confirmed loss. |
| `null_padding=true` success / count+schema match | 86 / 54 | A blanket option is neither safe nor strictly better; it can include headers/preambles as data. |
| Full-file sampling on the 42 structural mismatches | 0 newly matched | Raising `sample_size` alone did not fix these cases; it does not prove other cases never benefit. |

**Six confirmed successes-with-loss, all manually recoverable exactly:**

| Public original | Clean data rows → default rows | Inferred skip / annotated preamble | Distinct template |
|---|---:|---:|---|
| `Batch_3250493_batch_results.csv` | 9 → 8 | 1 / 0 | Survey results |
| `ResultsOR30x100-0.50_1.dat__m21.csv` | 23 → 22 | 1 / 0 | Optimization-result family |
| `ResultsOR30x100-0.50_3.dat.csv` | 32 → 31 | 1 / 0 | Same family, not independent |
| `ResultsOR30x100-0.75_10.dat__m13.csv` | 15 → 14 | 1 / 0 | Same family, not independent |
| `S30out.csv` | 302 → 100 | 202 / 0 | Wide table with width transition |
| `W44out.csv` | 302 → 100 | 202 / 0 | Same family, not independent |

The recovery check is stronger than row counts: with the annotated manual dialect/schema, the record multisets match all six cleaned targets exactly. The `S30out`/`W44out` loss is especially material: 202 of 302 intended records vanish with a successful default query. These six multi-column examples are outside the narrow one-column tail case addressed by PR #22; that statement is based on the PR scope, **not** a build of its branch.

**Strong trivial detection baseline:** `sniff_csv.SkipRows>0` flags 26/100 files. It flags all six confirmed loss cases but also 20 other files, including legitimate preambles and other table-shape issues. Against the *broader* row/column mismatch proxy it flags 23/42 mismatches with only 3 count/schema-matching flags. Therefore “just warn on inferred skip” is already a cheap, useful diagnostic baseline. A proposed smarter mechanism must prove real selectivity/repair beyond it rather than claim mere detectability. `null_padding` restores the row count in the six cases but in several includes an extra header as a data row or changes the inferred schema; it is not a universal correction.

**External benchmark caveat:** Pollock's [DuckDB Auto runner](https://github.com/HPI-Information-Systems/Pollock/blob/bd2a646f4cf55d2bd4e76df511c9c9f675ae7bcc/sut/duckdbauto/duck-bench.py#L1-L61) enables permissive options, times relation setup before materialization, and is not a pinned current-default evaluation. Its [metric code](https://github.com/HPI-Information-Systems/Pollock/blob/bd2a646f4cf55d2bd4e76df511c9c9f675ae7bcc/pollock/metrics.py#L55-L124) has row-concatenation collision risk. Thus [DuckDB's published Pollock scores](https://duckdb.org/2025/04/16/duckdb-csv-pollock-benchmark) are background, not our current numerical baseline. Our broad sweep also does **not** measure full-cell correctness for all 100, nor independent publisher holdout, latency distribution or RSS. No benchmark score or speedup is invented.

## 4. Why no core patch was justified

The observations pass **problem existence** but not the stronger **independent system contribution** gate. The three file templates largely share a `skip_rows`/candidate-selection failure; the affected one-column variant is already being patched upstream. The generic immediate remedy (warn/abstain when skip>0) is trivial and already exposes its input through `sniff_csv`, with nontrivial legitimate-preamble false alarms. Blanket `null_padding` trades one error for others. Existing CSV inference work already studies consistency, type evidence, preambles and abstention. A truly novel, bounded distinction has not emerged from the 100-file sweep, and no independent, correctly annotated held-out source beyond Pollock was available. Proceeding with a C++ rule now would repeat the user's earlier failed pattern: patch first, search for thesis later.

**Possible small upstream contribution:** coordinate with PR #22/#25827 maintainers and contribute additional regression tests covering the six public multi-column cases, perhaps a narrow behavior fix. This would be valid engineering, **not** the thesis core. No PR was opened or code changed here.

**Reopen conditions:** first obtain an independent publisher-held-out corpus with record truth; pre-register a decision problem and compare to `SkipRows>0`, `null_padding`, PR #22, and current DuckDB main. Require substantial reduction in verified silent-loss cases at low erroneous-abstention rate and bounded full-import latency/RSS—not just dialect-label accuracy. Only then design one C++ mechanism. If the best result is a warning or a handful of exception rules, permanently No-Go for this MSc thesis framing.

## 5. Reproduction and artifacts

Run from a fresh isolated directory; Pollock source in this audit was cloned sparse at commit `bd2a646f4cf55d2bd4e76df511c9c9f675ae7bcc`. Scripts use only DuckDB 2.0.0 plus Python standard library. To reproduce with a venv:

```bash
python3 -m venv /tmp/c18-venv
/tmp/c18-venv/bin/python -m pip install 'duckdb==2.0.0'
git clone --depth 1 --filter=blob:none --sparse https://github.com/HPI-Information-Systems/Pollock.git /tmp/c18-pollock
git -C /tmp/c18-pollock fetch --depth 1 origin bd2a646f4cf55d2bd4e76df511c9c9f675ae7bcc
git -C /tmp/c18-pollock checkout bd2a646f4cf55d2bd4e76df511c9c9f675ae7bcc
git -C /tmp/c18-pollock sparse-checkout set survey_sample survey pollock
cd <local-projects>/C18_csv_robustness_20261027
/tmp/c18-venv/bin/python scripts/known_issue_probe.py --output-dir results
/tmp/c18-venv/bin/python scripts/baseline_survey.py --pollock /tmp/c18-pollock --output results/survey100_baseline.json
/tmp/c18-venv/bin/python scripts/augment_sniff.py --input results/survey100_baseline.json --pollock /tmp/c18-pollock --output results/survey100_with_sniff.json
/tmp/c18-venv/bin/python scripts/extra_options.py --baseline results/survey100_with_sniff.json --pollock /tmp/c18-pollock --output results/survey100_extra_options.json
/tmp/c18-venv/bin/python scripts/oracle_six.py --pollock /tmp/c18-pollock --baseline results/survey100_with_sniff.json --output results/oracle_six.json
/tmp/c18-venv/bin/python scripts/summarize.py --baseline results/survey100_extra_options.json --oracle results/oracle_six.json --output results/summary.json
```

The source clone occupies ~292 MB due requested sparse paths. Exact raw outputs: `results/summary.json`, `results/survey100_*json`, `results/oracle_six.json`, `results/issue25827_probe.json`, and source CSV in `sources/Pollock/survey_sample`. `oracle_six.json` includes each exact SQL query. We did not benchmark current main binary; source audit establishes its relevant path still exists, while numerical results are **DuckDB 2.0.0** only. No C17 files were modified.
