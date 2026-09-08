# WoTEx Lab workbench

This is the non-umbrella Phoenix LiveView reference host owned by
[WLB.11](../../docs/specs/WLB.11-workbench-and-design-system.md). It consumes
the public Lab and profile-package APIs; the base `wotex_lab` library does not
depend on Phoenix.

The host exposes three bounded experiments, disposable session-owned Things,
scoped live metrics and downloadable evidence. Running an experiment never
approves a Thing Action. The smart-room experiment stops at a named, expiring
decision and dispatches only after the separate exact approval form passes the
policy and freshness checks again. Mounting or reconnecting starts no room or
experiment.

## Development

From this directory:

```sh
WOTEX_PATH_DEPS=1 mix setup
WOTEX_PATH_DEPS=1 mix phx.server
```

`WOTEX_PATH_DEPS=1` is the sole workspace switch. With it unset, dependencies
are resolved as versioned artifacts. The application never downloads chart
code: pinned Vega, Vega-Lite and Vega-Embed builds and their BSD licenses ship
under `priv/static/vendor/`. `elixir bin/provision_chart_assets.exs` is the
explicit digest-verifying renewal command.

The local completion gate is:

```sh
WOTEX_PATH_DEPS=1 mix check --no-retry
```

The host uses a small native check runner because its accepted location is two
levels below another Mix project, a shape that ex_check interprets as a possible
umbrella child. `.check.exs` remains the declarative list of the same checks.

## Runtime configuration

Production requires `SECRET_KEY_BASE`. Optional variables are `PHX_HOST`,
`PORT`, `WOTEX_LAB_WORKBENCH_SESSION_TTL_MS` and `WOTEX_LAB_MAUDE`. A Maude
path is verified and supervised explicitly; no configured engine is reported
as unsupported, never as successful evidence.

All rooms and their child processes are session-owned and bounded. Reports are
limited to one MiB, previews to 100 rows and 32 columns, charts to 2,000 points
per series and eight series, request bodies and LiveView frames to 64 KiB, and
metrics to the configured fixed-size ring.
