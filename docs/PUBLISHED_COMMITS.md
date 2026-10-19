# Published code provenance

This repository is a **source snapshot** rather than a Git fork containing upstream history. Its baseline commit has the exact Git tree of DuckDB upstream `f2b0bad0eb3e47e2060f1f07af9d2069eaf77ea1`. This was necessary because the local DuckDB history is shallow and blob-filtered; an initial full-history push was rejected by GitHub with a missing-object unpack error. No remote refs were created by that failed attempt.

To avoid publishing a personal email present in the local research commit metadata, A and B are publication commits using GitHub noreply. Their **Git tree IDs exactly match** the corresponding local final research commits. Public commit IDs differ; source and SQL-test content do not. The local original branches remain untouched.

| Contribution | Upstream/local source commit | Published commit | Exact Git tree |
|---|---|---|---|
| DuckDB baseline | `f2b0bad0eb3e47e2060f1f07af9d2069eaf77ea1` | `30ea6b500561738e94a6ce0f688fde944edcbc0c` | `0d050959d993a83e7868a1e75401a480afbbb2e5` |
| A, optimizer | `64bedbc0e7becc41e9914ff57a502c8f7d5aa7a5` | `d22d6143e44fe52561374f472325d23fdecb0c0e` | `be85a8af8bb7ec6350ecc6b8041556290ca72452` |
| B, execution | `435d7a420d4a768e2f701c49a824b2682d57c1be` | `42d4ca8f2f9c2d5188639b57f1a77df3f95be9a5` | `0fc950968ad2ffa0bffc99ace456c3068b0d6442` |

The net patches in `patches/` were generated from the upstream baseline to each original final tree. Both pass `git apply --check` against the clean baseline. The public B branch is the final code state, not the history of failed prototype steps. Those steps remain in the local C17 research archive.
