# Native SVG chart rendering

Decision date: 2026-09-08. Status: accepted. Owners: WLB.07, WLB.08 and
WLB.11. This decision supersedes only the chart-rendering selection in
[ADR 0005](0005-interactive-elixir-analytics.md); Explorer remains the optional
dataframe analysis engine.

## Context

The Nx/Elixir community evidence reviewed for ADR 0005 separates numerical
work, dataframe analysis and presentation. Explorer supplies an Elixir
dataframe API backed by Polars and is useful for bounded filtering and
aggregation, but it is not a chart renderer. VegaLite, Tucan, Kino.VegaLite
and Plotly-oriented packages are valuable when a consumer needs their broader
grammar or interactions. The Workbench does not: it admits only line, area and
point marks over bounded inline series and forbids caller expressions, signals,
transforms, URLs and arbitrary datasets.

The existing Elixir chart module already computes domains, ticks, gaps and mark
geometry after the bounded preview layer has performed any required
downsampling. The HEEx component can render that closed model directly as
browser-native SVG with a text/table alternative. Keeping the three
Vega browser libraries would preserve a second chart compiler and execution
surface for a grammar the host deliberately does not expose. The removed
Vega, Vega-Lite and Vega-Embed files totalled 832,280 bytes raw and 280,484
bytes gzipped in the reviewed source tree.

Contex and GGity were considered as server-side Elixir renderers. They are
reasonable package choices for broader plotting needs, but adopting either
would add another chart contract without replacing the Workbench's existing
geometry and missing-value semantics. No wrapper is selected merely to
serialize the already-supported descriptor.

## Decision

Explorer 0.12 remains an explicitly selected, optional Workbench analysis
dependency. `Wotex.Lab.Analytics` uses it only for admitted in-memory filtering
and aggregation, then materializes bounded rows and series with source/query
identity. Nx remains the numerical layer.

`WotexLabWorkbench.Chart.Admission` owns a closed, renderer-neutral descriptor.
`WotexLabWorkbench.Chart` computes bounded geometry, and the HEEx component is
the sole Workbench renderer. It emits native SVG for line, area and point marks,
preserves missing-value gaps, includes axes, ticks, legend and accessible
title/description, and keeps the maximum 100-row table representation in a
visible, keyboard-accessible disclosure.
LiveView replaces the server-owned SVG when admitted controls change.

The host does not ship Vega 6.4.0, Vega-Lite 6.4.3, Vega-Embed 7.2.0, a chart
JavaScript hook or a chart asset provisioner. It does not accept general Vega
specifications. Pan/zoom is intentionally absent from the accepted native
renderer; it must not be documented as available. A future interaction may be
admitted through bounded server controls with its own accessibility, lifecycle
and browser evidence. It must not silently reintroduce arbitrary client-side
chart code.

## Consequences

The browser no longer parses or compiles chart specifications, and the host
removes the chart npm/provisioning, license and global-script surfaces. Chart
updates remain dynamic because LiveView and Explorer recompute the admitted
analysis and replace the SVG; "dynamic" does not require a general client-side
visualization runtime.

The smaller implementation has one geometry contract for source tests and
rendering. Acceptance still requires malformed-input ceilings, line/area/point
parity, negative/flat/all-missing/gapped cases, semantic color classes,
accessible descriptions and tables, theme/reflow checks and source-versus-
artifact evidence. Rich arbitrary specifications and local pan/zoom are not
features of this host; consumers that need them may compose a different
renderer without changing Lab evidence or WoT semantics.
