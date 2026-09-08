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
Node is needed for the dependency-free chart-hook tests, not by the running
Elixir host. The exact Decimal 3.1.1 advisory acknowledgement is documented in
the Lab's [dependency review](../../docs/provenance/standards-and-dependencies.md)
and protected by the host's own locked-version and bounded-parser regression.

## Interactive charts and browser evidence

The host explicitly selects Explorer 0.12.0 and invokes the shared
`Wotex.Lab.Analytics` profile when “Apply analysis” is submitted. Series and
inclusive event-time filters, line/point/area selection and compatible-unit
comparisons are read-only: they cannot re-run an experiment or change its
evidence. Summaries distinguish observations, missing and nonfinite values;
tables show at most 100 rows and both source and query digests. Empty ranges
are not measured zeros. Reload does not replay the query. No `kino_explorer`
dependency, arbitrary SQL/expression or browser-selected instance is admitted.

Vega Embed uses its bundled CSP interpreter (`ast: true`); neither
`unsafe-eval` nor a fourth script is required. The renderer cannot load URLs.
The hook applies only a fixed horizontal pan/zoom interaction, follows theme
changes, resets by keyboard and finalizes obsolete views. Accessible SVG and
the maximum 100-row table remain available when enhancement fails. The SVG
supports all three admitted marks and preserves missing-value gaps.

Tensor previews split the lazy batch before stacking and slice before copying
to host lists. Their observed/filled counts describe only the shown elements,
with row/feature/vector truncation disclosed. Min/max downsampling keeps gap
sentinels around retained extrema; it cannot draw a line across an omitted gap.
Its interval is input points per bucket, not an assumed event-time duration.

The optional browser gate requires an explicitly installed Playwright/browser
cohort and a disposable local server. It never downloads them. For example,
start the host with `PORT=4107 WOTEX_PATH_DEPS=1 mix phx.server`, then run:

```sh
node bin/check_chart_browser.cjs http://127.0.0.1:4107
```

Supply Playwright through your tool environment (for example `NODE_PATH`). The
script reports actual Node, Playwright and Chromium versions. The 2026-09-08
source cohort passed with Node 26.8.1, Playwright 1.63.0-alpha-2026-08-31 and
Chromium 153.0.8010.12; this is neither a stable-browser compatibility matrix,
WCAG certification nor installed-artifact evidence.

## Runtime configuration

Production requires `SECRET_KEY_BASE`. Optional variables are `PHX_HOST`,
`PORT`, `WOTEX_LAB_WORKBENCH_SESSION_TTL_MS` and `WOTEX_LAB_MAUDE`. A Maude
path is verified and supervised explicitly; no configured engine is reported
as unsupported, never as successful evidence.

All rooms and their child processes are session-owned and bounded. Reports are
limited to one MiB, previews to 100 rows and 32 columns, charts to 2,000 points
per series and eight series, request bodies and LiveView frames to 64 KiB, and
metrics to the configured fixed-size ring.
