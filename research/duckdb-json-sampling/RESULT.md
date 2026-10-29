> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# DuckDB multi-file JSON schema-sampling buffer gate (2026-10-25)

## Decision

**GO to propose a small upstream fix of [DuckDB #27826](https://github.com/duckdb/duckdb/issues/27826), not a thesis core optimization.** The reporter identified the per-sampled-file 32 MiB memory-limit problem; this work does not claim that diagnosis as original. Our isolated one-line behavioral change (plus regression test) releases the schema scan's final buffer when a file's sample is complete. It leaves the retained `JSONReader` object and file state intact for execution. Local Release, ASan, and UBSan JSON suites pass; upstream CI/maintainer review has **not** occurred. No PR has been submitted here.

This is a *JSON-ingestion-specific* resource-lifetime fix. It is useful for globs with many small/medium files under a configured DuckDB memory limit, but does **not** establish a cross-operator bottleneck, broad latency win, or dissertation-sized contribution. A/B grouped Top-K and the stopped Compact Spill/TupleData/full-sort gates remain separate prior work. This small fix should not be relabeled as their generalized “C”.

## Source and ownership audit

- Pin both worktrees at `1641475ef1db08ec063631ff6a8f08d9d6736ae7`: clean baseline `C17-DuckDB-Agg-Metadata-Baseline-20261025` and isolated candidate `C17-DuckDB-JSON-Sample-Candidate-20261025`. The dirty `C17` main working tree was not used for either binary or touched for source changes.
- `extension/json/json_functions/read_json.cpp:68-90` creates a `JSONReader` per sampled file and scans with a nominal `2 * maximum_object_size` buffer (32 MiB by default). `:123-129` is the candidate release site.
- `extension/json/json_reader.cpp:886-897` already shrinks the initial auto-detect buffer (the earlier [#26938](https://github.com/duckdb/duckdb/pull/26938) change). `:1167-1183` grows the recycled buffer back to full capacity before a subsequent read ([#27419](https://github.com/duckdb/duckdb/pull/27419)). For a short nonempty file, the end-of-file probe can insert that full-sized, zero-byte buffer into the reader map (`:1122-1141`). The schema task does not otherwise decrement its final handle; sampled readers stay live through binding. `JSONReaderScanState::ClearBufferHandle()` in `json_reader.cpp:421-432` is the existing mechanism to decrement usage/remove that buffer. This is a source-level mechanism inference corroborated by the memory-limit failures, **not** a direct allocation-stack measurement.
- The fetched #27826 issue page was open and displayed no linked branch/PR on 2026-10-25. Recheck before submitting; upstream can change quickly.

## Patch

In the isolated candidate worktree only:

```cpp
// The schema scan is complete; do not retain its final buffer in the sampled reader.
scan_state.ClearBufferHandle();
```

The new SQLLogicTest `test/sql/json/table/read_json_schema_buffer_release.test` uses 32 files, 500MB limit, and a field present only in the last file to check both completion and schema coverage, with and without `union_by_name`. `candidate.patch` includes both source and test. No new mode, tuning threshold, dependency, or data-path restructuring is introduced.

## Reproduction

Build the same pinned source and Release settings in the two worktrees, applying `candidate.patch` only to the candidate. CLI paths used here:

```text
<local-projects>/C17-DuckDB-Agg-Metadata-Baseline-20261025/build/research-release/duckdb
<local-projects>/C17-DuckDB-JSON-Sample-Candidate-20261025/build/research-release/duckdb
```

The upstream `main` ref returned the pinned SHA `1641475ef1db08ec063631ff6a8f08d9d6736ae7` on 2026-10-25. Relevant build commands (the baseline does not need the unit-test target):

```sh
cmake -S . -B build/research-release -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_COMPLETE_EXTENSION_SET=ON -DBUILD_SHELL=ON -DBUILD_UNITTESTS=ON
cmake --build build/research-release --target duckdb unittest -j 8
build/research-release/test/unittest 'test/sql/json/table/*'
```

`ENABLE_SANITIZER=ON` in the Release cache does **not** mean the Release binaries above were instrumented: `RELEASE_SANITIZER=OFF`. The separate sanitizer builds were configured as follows; Ninja commands confirmed `-fsanitize=address` and `-fsanitize=undefined`, respectively:

```sh
cmake -S . -B build/research-asan -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DRELEASE_SANITIZER=ON -DENABLE_SANITIZER=ON -DENABLE_UBSAN=ON \
  -DDISABLE_VPTR_SANITIZER=ON -DBUILD_UNITTESTS=ON -DBUILD_SHELL=ON \
  -DBUILD_COMPLETE_EXTENSION_SET=ON
cmake --build build/research-asan --target unittest duckdb -j 8
ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 \
  build/research-asan/test/unittest 'test/sql/json/table/*'

cmake -S . -B build/research-ubsan -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SANITIZER=OFF -DENABLE_UBSAN=ON -DFORCE_ASSERT=ON \
  -DDISABLE_VPTR_SANITIZER=ON -DBUILD_UNITTESTS=ON -DBUILD_SHELL=OFF \
  -DBUILD_COMPLETE_EXTENSION_SET=ON
cmake --build build/research-ubsan --target unittest -j 8
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  build/research-ubsan/test/unittest 'test/sql/json/table/*'
```

Run from `C17` (macOS `/usr/bin/time -l` is required for RSS collection):

```sh
python3 results/research_gap/json_multifile_gate_20261025/run_tiny_matrix.py \
  <local-projects>/C17-DuckDB-Agg-Metadata-Baseline-20261025/build/research-release/duckdb \
  /tmp/c17_json_gate_20261025/matrix \
  results/research_gap/json_multifile_gate_20261025/raw/baseline_tiny.json 3
python3 results/research_gap/json_multifile_gate_20261025/run_tiny_matrix.py \
  <local-projects>/C17-DuckDB-JSON-Sample-Candidate-20261025/build/research-release/duckdb \
  /tmp/c17_json_gate_20261025/matrix \
  results/research_gap/json_multifile_gate_20261025/raw/candidate_tiny.json 3
python3 results/research_gap/json_multifile_gate_20261025/run_medium_matrix.py \
  <local-projects>/C17-DuckDB-Agg-Metadata-Baseline-20261025/build/research-release/duckdb \
  <local-projects>/C17-DuckDB-JSON-Sample-Candidate-20261025/build/research-release/duckdb \
  /tmp/c17_json_gate_20261025/medium32 \
  results/research_gap/json_multifile_gate_20261025/raw/medium_matrix.json 3
python3 results/research_gap/json_multifile_gate_20261025/run_correctness_pairs.py \
  <local-projects>/C17-DuckDB-Agg-Metadata-Baseline-20261025/build/research-release/duckdb \
  <local-projects>/C17-DuckDB-JSON-Sample-Candidate-20261025/build/research-release/duckdb \
  /tmp/c17_json_gate_20261025/correctness \
  results/research_gap/json_multifile_gate_20261025/raw/correctness_pairs.json
python3 results/research_gap/json_multifile_gate_20261025/run_pipe_pair.py \
  <local-projects>/C17-DuckDB-Agg-Metadata-Baseline-20261025/build/research-release/duckdb \
  <local-projects>/C17-DuckDB-JSON-Sample-Candidate-20261025/build/research-release/duckdb \
  results/research_gap/json_multifile_gate_20261025/raw/pipe_large_pair.json
```

All test inputs above are generated by the scripts; no production dataset is claimed. The primary query is `SELECT count(*), sum(id) FROM read_json('<glob>')` with `threads=1`, `memory_limit='500MB'`, and 9-byte per-file input in the tiny matrix. `run_medium_matrix.py` uses 32 rows/files with one 1 MiB string payload per row and sums `length(payload)`.

## Measured result

| Workload / DuckDB memory limit | Baseline | Candidate | Interpretation |
|---|---:|---:|---|
| 1, 4, 8 tiny files / 500MB | 3/3 pass each | 3/3 pass each | No failure to fix. |
| 16 tiny files / 500MB | 0/3 pass | 3/3 pass | Candidate crosses success boundary. |
| 32 tiny files / 500MB | 0/3 pass | 3/3 pass | Baseline reports failed 32 MiB allocation. |
| 32 tiny files / 40MB | 0/3 pass | 3/3 pass | Illustrates difference in minimum tested configured limit. |
| 32 tiny files / 1200MB | 3/3 pass | 3/3 pass | Baseline eventually completes. |
| 32 tiny files / 1500MB | 3/3 pass | 3/3 pass | No meaningful latency claim from tens-of-ms one-shot CLI runs. |
| 32 × ~1 MiB files / 200 or 500MB | 0/3 pass at either limit | 3/3 pass at either limit | Correct result: 32 rows, 33,554,432 payload bytes. |
| 32 × ~1 MiB files / 1200MB | 3/3 pass | 3/3 pass | Median peak RSS: baseline 92.62 MiB; candidate 60.39 MiB. |

Raw per-run exit code, SQL, stdout, elapsed wall time, and `time -l` max RSS are in `raw/*.json`. The 40/500/1200MB points are **not** an exact threshold search.

**Memory accounting caveat:** DuckDB `memory_limit` is not physical resident memory. For 32 tiny files at 1500MB, baseline median max RSS is only about 31.8 MiB and candidate about 31.0 MiB: most of the large charged buffers were not resident/touched. Do not claim ~1 GiB peak RSS reduction. For 1 MiB values at 1200MB, a ~32 MiB RSS reduction is observable on this macOS machine, but not a platform-independent guarantee. Neither cumulative allocation nor throughput/concurrency has been measured.

Setting `maximum_sample_files=1` also avoids the failure but can miss a field present only in the last of 32 heterogeneous files in default `read_json`; `raw/sampling_loss.json` records `DESCRIBE` including `new_text` under default sampling and omitting it with that option. It is not a semantics-preserving replacement. With `union_by_name=true`, DuckDB can inspect all files, so the limitation of this workaround is specific to the default sampling scenario.

## Verification and limits

- Release candidate: JSON table suite `build/research-release/test/unittest 'test/sql/json/table/*'` passed **6070 assertions / 28 cases**, with one `httpfs`-requiring test skipped; the new test passed 38 assertions. The many-files slow test passed 4003 assertions, auto-detect slow test 162. Separate ASan- and UBSan-instrumented Release builds passed the same JSON table suite (6070 assertions, same `httpfs` skip); the new test passed 38 assertions in each. ASan leak detection was disabled, so no leak-check claim is made. Captured logs are under `raw/logs/`.
- Nine Release baseline/candidate differential queries match exit code and stdout: heterogeneous schema, explicit columns, full sampling, JSON arrays, parallel NDJSON, gzip, empty file, 8 MiB value, and malformed input error. Details in `raw/correctness_pairs.json`. A single-file `/dev/stdin` pipe smoke produced the same `2,3` result on both builds. More importantly, a 41.2 MB non-seekable `/dev/stdin` stream with `sample_size=1` produced the same 10,000 rows and 40,960,000 payload bytes in both builds (`raw/pipe_large_pair.json`); mixed pipe/file behavior was not validated.
- The new code uses an existing buffer-release method, but full exception-behavior coverage, cross-platform safety, and upstream style/semantics still require maintainer review and CI.
- There is **no production-data benchmark, p95 latency, concurrent throughput test, Windows/Linux RSS measurement, or broad operator benefit**. This is a well-grounded, narrow upstream fix candidate; it is **not** proof of a general executor optimization or a new thesis center.
