# Runtime and toolchain baseline

The WBM-C05 release-candidate gate uses this exact source and execution cohort:

| Input | Exact value |
|---|---|
| `wotex` | `58409779ae9515df2bf120a5f13813cffcb1c59c` |
| `wotex_runtime` | `70f9511b8b691665b0c87d84f743891c70c93b9e` |
| Elixir | `1.18.4-otp-27` |
| Erlang/OTP | `27.3.4.15` |

The default local gate selects the sibling checkouts only when
`WOTEX_PATH_DEPS=1`; release-shaped archive metadata always retains the normal
`wotex ~> 0.1.0` and `wotex_runtime ~> 0.1.0` requirements. Hosted CI checks
out the exact revisions above instead of moving branches.

This is one verified toolchain pair, not the entire `elixir: "~> 1.18"`
compatibility range. The exact commits must be available on the selected remote
before hosted CI can resolve them, and compatible packages must exist in the
selected registry before a public dependency installation can succeed. Neither
condition is inferred from this local candidate.
