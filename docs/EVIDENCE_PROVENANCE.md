# Published evidence provenance

The public raw timing CSVs are copies of formal local run tables with **only** `loaded_lib` changed: its local absolute file path was removed and the column was renamed `loaded_lib_role`, whose value is the already recorded `mode`. Timing, query identity, session/run, row count and result fingerprints were not changed. This redaction avoids publishing a personal filesystem path. Summary and SQL field values were copied without transformation; published CSV line endings were normalized to LF. No experiment was rerun for this publication.

Source SHA-256 hashes before redaction/copy:

| Experiment | File | Original SHA-256 |
|---|---|---|
| `20261018_008` | `raw_runs.csv` | `7897cee7119d5f155b5844a936b360382d988e50f50e2dd4ad3543f7f75c1eef` |
| `20261018_008` | `summary.csv` | `331966442d5e331ba0936bc0738e2ed9965177cb3e6dd9a6e5c876c96cdace8e` |
| `20261018_009` | `raw_runs.csv` | `d0e964bc7192354c44381d8e706f7c9e4f6e33d986511cf36041cccfa78cf0f7` |
| `20261018_009` | `summary.csv` | `7e309f98a62ff8cabe2c44adbef958d8b7d3978f3216b34fed6dd2df23996e2f` |
| `20261018_011` | `raw_runs.csv` | `c42a694ddedba870fd3af3852e8ae4383aacdcecc44475b76107581062937067` |
| `20261018_011` | `summary.csv` | `6c2f1d6e6a6fe375c9c9f909d93482c9a0ce180397d0c999d45d85bf56f57da5` |

The original full experiment directories are retained in the local `results/aggregate_pruning/experiments/` archive. Public CSVs are a selected evidence subset; large database inputs, binary drivers, full profiler traces and machine-local logs are not included.
