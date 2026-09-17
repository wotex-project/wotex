# Runtime compatibility evidence

The package requirement is Elixir `~> 1.18`. Runtime evidence is narrower than
that version expression. On 2026-09-14, the source and locked dependency graph
passed isolated local lanes for these cohorts:

| Lane | Elixir | Erlang/OTP | Evidence |
| --- | --- | --- | --- |
| minimum | 1.18.4 | 27.3.4.15 | locked dependency resolution, warnings-as-errors project compilation, formatting, 73 tests and 3 doctests, and all ten portable schema mirrors |
| current | 1.20.4 | 29.0.4 | the minimum-lane checks plus documentation, package archive construction, out-of-tree archive compilation, and archive-only consumer execution |

Each lane used separate temporary `MIX_BUILD_PATH` and `MIX_DEPS_PATH` values.
This prevents BEAM files, Rebar build state, dependency `priv` links, and
Dialyzer persistent lookup tables from crossing runtime cohorts. The
reproducible command sequence for a provisioned runtime is:

```console
WCF_COHORT_ROOT="$(mktemp -d)"
WCF_COHORT_ROOT="$(cd "$WCF_COHORT_ROOT" && pwd -P)"
MIX_BUILD_PATH="$WCF_COHORT_ROOT/build" \
  MIX_DEPS_PATH="$WCF_COHORT_ROOT/deps" \
  MIX_ENV=test mix deps.get --only test --check-locked
MIX_BUILD_PATH="$WCF_COHORT_ROOT/build" \
  MIX_DEPS_PATH="$WCF_COHORT_ROOT/deps" \
  MIX_ENV=test mix check --no-retry
MIX_BUILD_PATH="$WCF_COHORT_ROOT/build" \
  MIX_DEPS_PATH="$WCF_COHORT_ROOT/deps" \
  MIX_ENV=test mix test test/wotex/conformance/schema_test.exs
```

The current lane additionally runs the following commands with the same three
environment values:

```console
mix docs --warnings-as-errors
mix hex.build
mix run --no-start bin/check_archive.exs
```

The ignored local tracker records the exact source commit, archive digest,
corpus digests, runtime patch releases, dependency cohort, commands, and exit
codes. Those execution records are machine-local evidence and are excluded from
the package archive.

This evidence does not cover every Elixir `1.x` and Erlang/OTP combination,
another operating system or architecture, future dependency resolution, or a
published package. The development API remains unstable. Remote workflow
configuration is not evidence that a hosted run completed.
