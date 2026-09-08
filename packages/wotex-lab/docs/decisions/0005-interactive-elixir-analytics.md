# Interactive Elixir analytics

Decision date: 2026-09-08. Status: accepted. Owners: WLB.03, WLB.07,
WLB.08, WLB.10 and WLB.11. This decision changes the reference analytics
composition, not WoT semantics or the numerical first-run dependency closure.

## Evidence and interpretation

Elixir Forum's Nx discussions distinguish dataframe processing, numerical
computation and presentation rather than proposing one replacement for all three:

- [Jose Valim, February 2023](https://forum.elixirforum.com/t/data-science-and-machine-learning-workflows-in-elixir/53659/2)
  recommends Explorer's Rust/Polars backend for dataframe work. Native compute
  behind an Elixir API is intentional; pure BEAM computation is not the goal.
- [Paulo Valente, January 2023](https://forum.elixirforum.com/t/generate-spiral-data-with-nx/53314/4)
  distinguishes Nx-to-VegaLite plotting from a need for Explorer.
- [A dataframe comparison, November 2023](https://forum.elixirforum.com/t/plot-with-two-dataframes/59490/4)
  uses Tucan layers. [Tucan's author, October 2024](https://forum.elixirforum.com/t/tucan-a-plotting-library-on-top-of-vegalite/57938/24)
  announces pan/zoom support. Vega-Lite is not intrinsically static.
- [Alex Koutmos, August 2026](https://forum.elixirforum.com/t/elixir-for-finance-self-published/76385/1)
  describes current use of Nx, Scholar, Explorer, Livebook and Vega-Lite for
  interactive analysis. This is evidence of usage, not a universal endorsement.
- [Plotly_ex, March 2026](https://forum.elixirforum.com/t/plotly-ex-interactive-plotly-js-charts-for-elixir-works-in-livebook-via-kino-and-in-phoenix-liveview/74693)
  is a relevant alternative in the adjacent Livebook/LiveView community. It
  still requires Plotly.js and is not a Kino Explorer successor. It is not an
  admitted dependency; switching renderers requires its own parity/security
  evidence, not an additional mandatory renderer in this host.

## Selected boundaries

Explorer is the optional dataframe analysis profile. Nx/Scholar is the
numerical layer when the operation warrants tensors. Neither is a renderer,
telemetry store, authorization mechanism or mandatory first-tensor dependency.
The explicit workbench host may select Explorer; notebook consumers opt in.

Keep the bounded Vega-Lite renderer and its local, digest-pinned assets. The
Elixir VegaLite/Tucan ecosystem informs the shared descriptor, but arbitrary
specifications produced by these libraries are not automatically admitted:
schema versions, marks, expressions, selections and resource bounds differ.
Normalize through Lab's closed contract before rendering. Do not add a
wrapper dependency merely to serialize an already-supported descriptor.

HEEx owns server-admitted filters, selected series, mark choice and resets.
The hook owns local rendering, safe fixed pan/zoom configuration, update races
and disposal. Browser selections do not alter raw evidence, execute queries
without admission, or authorize an Action. SVG and bounded tables remain
accessible fallbacks; they are not the primary analytical experience.

Analysis preserves source identity, units, order, missing/nonfinite state and
the distinction between a preview, live lossy metrics and an immutable dataset.
Filter and aggregate with Explorer before materializing bounded browser rows.
No silent nil-to-zero tensor conversion, hidden learned normalization or
training from moving diagnostic history. WLB.03 retains split-before-window
and train-only normalization requirements.

## Adoption checks are not waived

`livebook-dev/kino_explorer` is archived. No maintainer-announced successor was
established by the forum/repository research. Do not adopt it in a new required
profile or describe core Kino as its successor. Core `Kino.DataTable` over a
bounded preview and a purpose-built `Kino.Table` adapter are explicit local
integration choices; neither claims parity with the archived transformation
Smart Cell. Automated scenarios must work without that Smart Cell.

Decimal remains subject to the normal dependency audit. The maintainer's
[CVE advisory](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v)
identifies versions before 3.0.0 as affected, whereas the EEF machine-readable
range inspected on this decision date lacks a fixed event and flags 3.1.1.
The reviewed cohort uses Decimal 3.1.1 and retains bounded string parsing.
Any acknowledgement must name this advisory, the locked version, evidence
and date; it cannot suppress unrelated vulnerabilities or unsafe contexts
with infinite precision/exponent limits. Renew the check when either changes.

## Acceptance

Each implementation slice needs bounded and malformed-input tests, explicit
dependency/profile evidence and logical local commits. Chart acceptance adds
updated/destroyed hook tests, out-of-order render completion, failed rendering,
empty/all-missing/negative/flat/gapped data, mark parity, a maximum 100-row
table preview and keyboard-equivalent server controls. Explorer acceptance
adds filter/aggregate parity, null counts, source/query digests, unit isolation,
work limits and native failure reporting. Browser and artifact evidence remain
separate from source tests. No source-only gate closes WLB.08.
