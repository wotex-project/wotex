# Runtime and toolchain baseline

The WBM-C05 release-candidate gate was recorded with this exact source and
execution cohort:

| Input | Exact value |
|---|---|
| `wotex` | `58409779ae9515df2bf120a5f13813cffcb1c59c` |
| `wotex_runtime` | `70f9511b8b691665b0c87d84f743891c70c93b9e` |
| Elixir | `1.18.4-otp-27` |
| Erlang/OTP | `27.3.4.15` |

Both commits belong to the former per-package repositories and predate the
move into this repository. The package gate now selects the `wotex` and
`wotex-runtime` packages of the same commit from `packages/`, and only when
`WOTEX_PATH_DEPS=1`; release-shaped archive metadata always retains the normal
`wotex ~> 0.1.0` and `wotex_runtime ~> 0.1.0` requirements. Hosted CI checks
out one exact commit of the repository instead of a moving branch. The
Elixir/OTP pair is the minimum CI lane in `tooling/packages.yaml`.

This is one verified toolchain pair, not the entire `elixir: "~> 1.18"`
compatibility range. The exact commit must be available on the selected remote
before hosted CI can resolve it, and compatible packages must exist in the
selected registry before a public dependency installation can succeed. Neither
condition is inferred from this local candidate.
