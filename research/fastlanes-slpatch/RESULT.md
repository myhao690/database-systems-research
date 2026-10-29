> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# FastLanes SLPATCH: exact exception-bound interval enumeration — 2026-10-26

## Decision

**Go for a small upstream C++ PR candidate; not a complete MSc thesis or a DuckDB query-execution optimization.** This is a stronger, isolated successor to `../fastlanes_slpatch_prefix_20261026/`, not a new threshold or a compression format change. It removes provably ineligible SLPATCH intervals from candidate evaluation while retaining the original option order and tie-breaking. On pinned FastLanes `dev` SHA `f0edc1020a538f1f8098640fce8347c9ac247a0d`, 10 interleaved native/prefix/bound runs per dataset found `to_fls` write-phase p50 improvements over native of 1.83–8.54× on 6/8 real datasets; the other two are approximately neutral. Versus the earlier prefix patch, p50 improves 1.20–2.82× on those six and is nearly unchanged on the other two. All 80 three-way real-data triplets were byte-identical. No heap allocation or on-disk format change was added.

The main C17/DuckDB repository's pre-existing edits were not touched. The C++ patch is saved as local commit `b01d44345d6adc262bcb91a6ba3808e1c28d84cf` on isolated FastLanes branch `research/slpatch-exception-bound-20261026` and archived here as `patches/exception_bound.patch`; the two diffs match byte-for-byte. The clean baseline worktree is `C17-FastLanes-C21-Baseline-20261026`; the patch passes `git apply --check` there. Nothing was submitted upstream.

## Mechanism and scope

Source: [`src/expression/analyze_operator_impl.hpp`](https://github.com/cwida/FastLanes/blob/f0edc1020a538f1f8098640fce8347c9ac247a0d/src/expression/analyze_operator_impl.hpp#L116-L275). In the native analyzer, every `(i,j)` histogram interval is scored, then discarded if it has `>= LOCAL_EXC_LIMIT_C` exceptions. The earlier prefix patch removed repeated interval summation but still scored O(k²) options. In the new helper, `excluded_left` and `excluded_right` identify only intervals with fewer than the **existing** 20-exception limit. Histogram repetitions are positive; thus there are at most 20 eligible start endpoints and 20 eligible end endpoints, giving O(E²) option scoring after histogram creation, where E=20. An `n_t` cast avoids GCC's signed/unsigned `-Werror` comparison failure.

For each eligible start `i`, end `j` still advances in the native ascending order. Ineligible intervals could never update `best` because the original code requires `next.n_exceptions < LOCAL_EXC_LIMIT_C`; the strict `size() < best.size()` tie rule is unchanged. `n_non_exceptions = 1024 - excluded_left - excluded_right` is the same histogram count as the native interval sum. This establishes an exact-work reduction rather than an approximate chooser. The forced-SLPATCH test is self-generating and checks decode equality, including nulls and high distinctness.

The patch only affects SLPATCH integer analysis used by [FastLanes Wizard expression trials](https://github.com/cwida/FastLanes/blob/f0edc1020a538f1f8098640fce8347c9ac247a0d/src/wizard/wizard.cpp#L685-L812) and final SLPATCH encoding. It does not improve CSV ingestion, decoding, other encodings, DuckDB runtime, compression ratio, or query throughput. The [VLDB 2025 FastLanes design](https://vldb.org/pvldb/vol18/p4629-afroozeh.pdf) already curates expression candidates and samples; do not claim candidate sampling as this work's novelty. Public issue/PR audit on 2026-10-26 found no matching interval-bound optimization, but cannot rule out private or later work.

## Interleaved Release evidence

Apple M4 Pro, macOS arm64, clang 23.1.1, same Release flags and pinned `cwida/FastLanes_Data` SHA `b1b375f46b29f25e305a7406a86369a8585dee98`. Each repeat rotates native/prefix/bound order. The probe measures `Connection::to_fls` write-phase wall time **after** `read_csv`, so this is not end-to-end load or service throughput. `p95` is nearest-rank at n=10: a tail descriptor, not a stable population estimate. Full paired observations, output SHA-256 values, and order are in `raw/interleaved_10x3_runs.csv`.

| Dataset | Native p50 ms | Prefix p50 ms | Bound p50 ms | Native/Bound | Prefix/Bound | Bound faster than prefix pairs |
|---|---:|---:|---:|---:|---:|---:|
| Food | 355.895 | 117.440 | 41.681 | 8.54× | 2.82× | 10/10 |
| FHV | 129.372 | 62.491 | 44.373 | 2.92× | 1.41× | 10/10 |
| orders | 438.529 | 181.443 | 113.772 | 3.85× | 1.59× | 10/10 |
| bgg | 310.025 | 184.186 | 153.265 | 2.02× | 1.20× | 10/10 |
| Bimbo | 35.961 | 24.049 | 19.630 | 1.83× | 1.23× | 10/10 |
| customer | 728.765 | 355.823 | 265.306 | 2.75× | 1.34× | 10/10 |
| Computer_Monitor | 7.666 | 7.764 | 7.668 | 1.00× | 1.01× | 4/10 |
| AMPds | 25.350 | 24.713 | 24.056 | 1.05× | 1.03× | 8/10 |

The two short-query results are effectively neutral, not evidence of universal speedup. Prefix diagnostic CPU-time profiling had shown substantial residual SLPATCH candidate cost after the first patch (see `raw/c21_profile_cpu_matrix*`); those diagnostic numbers motivated this exact-bound test and are **not** speedups. Real-data file sizes and hashes were equal across all three variants in all 80 triplets. A one-line type cast was needed for strict GCC compilation; the displayed timing run and all final tests are **after** that fix. The pre-cast 10×3 dataset remains archived separately for audit.

Three `/usr/bin/time -l` process-RSS samples per variant on Food/orders/customer found no consistent footprint shift; medians (native/prefix/bound) were Food 57.9/56.3/56.9 MB, orders 120.1/119.7/119.5 MB, customer 165.0/164.6/165.3 MB. This is **not** enough to prove equal peak RAM or concurrency capacity. The source adds no heap allocation. The demonstrated resource saving is CPU/write elapsed time, not memory or I/O volume.

## Correctness, portability, and known gap

- Final patched clang Release build and `git diff --check` passed. The self-generated forced-SLPATCH GTest passed 1/1, existing `unit_test` passed 97/97, and `quick_fuzz_test` passed 10/10. Logs are under `raw/`.
- A separate deterministic forced-SLPATCH matrix covered 12 shapes (ascending/descending distinct, skew, exception counts around 20, uniform/random, nulls, signed extrema). All 24 native/patched decode roundtrips passed; all 12 file pairs were byte-identical. `scripts/force_cases.py` and `raw/forced_cases.csv` reproduce it. This extends but does not exhaust input coverage.
- The earlier prefix patch built on macOS x86_64 under Rosetta and on Linux/aarch64 GCC 13; its Food file matched native/macOS bytes. The present exception-bound patch **also passed Linux/aarch64 GCC 13 Release** under Docker (`--cpus=2 --memory=4g -j2`), and its Food output matched native/macOS bytes (SHA-256 `0c059191e3677dbca91fe4108bd2fcdedb2bee9f130832a5b0e9d72d5483e748`). The first Linux attempt exposed a new `-Werror=sign-compare` failure; it was fixed by an explicit `n_t` cast and the same strict build then passed. This is a Linux build plus one-workload check, not the full Linux test suite; see `raw/build_retry.log`, `raw/run.log`, and `raw/arch.txt`.
- A final ASan+UBSan Debug build passed. Its forced-SLPATCH roundtrip succeeded and produced the same bytes as the unsanitized/native versions, with **0 observed ASan errors**. UBSan still logged 128 unaligned-load diagnostics beginning at `src/alp/src/fastlanes_gen_unffor.cpp:12676`, the same generated-decoder issue independently observed in native and prefix. Thus the sanitizer run is **not UBSan-clean**; track that existing decoder issue outside this performance PR. Logs are archived in `raw/c21_bound_sanitize_*`.
- Rust crate builds a separate `rust/vendor/fastlanes` snapshot. `rust/README.md` describes refresh before crate publishing; `make update-fastlanes-src` would delete/recreate it and auto-commit. The C++ candidate intentionally leaves that vendor copy untouched pending maintainer policy.

## Reproduce

At the pinned FastLanes SHA, apply `patches/exception_bound.patch` to a clean second checkout. Data paths and input hashes are documented in `../fastlanes_slpatch_prefix_20261026/raw/input_sha256.txt` and its README. Compile baseline, earlier prefix, and bound with identical Release settings. On this machine:

```sh
ARCHIVE=/path/to/C17/results/research_gap/fastlanes_slpatch_exception_bound_20261026
FASTLANES_DATA_DIR="$PWD/data" cmake -S . -B build/c21-release-localdata -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DFLS_BUILD_EXAMPLES=ON -DFLS_BUILD_BENCHMARKING=OFF \
  -DFLS_BUILD_TESTING=OFF -DCMAKE_C_COMPILER=/opt/homebrew/opt/llvm/bin/clang \
  -DCMAKE_CXX_COMPILER=/opt/homebrew/opt/llvm/bin/clang++ -DCMAKE_CXX_FLAGS=-Wno-error=nonnull
cmake --build build/c21-release-localdata --target cpp_example -j 6
/opt/homebrew/opt/llvm/bin/clang++ -std=c++20 -O3 -DNDEBUG -I src/include -I src -I build/c21-release-localdata \
  -o /tmp/c21_probe_bound "$ARCHIVE/../fastlanes_slpatch_prefix_20261026/scripts/probe.cpp" \
  build/c21-release-localdata/src/libFastLanes.a -lpthread
python3 "$ARCHIVE/scripts/compare_three.py" 10
```

Set the three binary paths and `/tmp/c21_data/` folders in `scripts/compare_three.py` when reproducing elsewhere. `scripts/resource_probe.py` is macOS-specific. The new GTest needs `-DFLS_BUILD_TESTING=ON`; this clang 23 environment also required `-Wno-error=character-conversion` for GoogleTest. No benchmark or data file is overwritten in the upstream tree.

## Thesis and PR boundary

This is a credible **upstream performance patch** for a real, cross-dataset compression-time bottleneck, subject to Linux and maintainer review. It is **not** a complete thesis project by itself: the code change is local to SLPATCH and does not show broader execution-strategy or representation insights. A thesis can use it as an evaluated first artifact, but should not inflate it into a general-purpose adaptive selector without new, independent evidence. If the remaining candidate-selection cost is not material after this exact fix, stop this lane and choose a different core project rather than adding thresholds or a learned model.
