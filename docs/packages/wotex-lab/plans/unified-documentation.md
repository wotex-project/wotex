# Unified documentation implementation plan

This plan implements
[WLB.12](../specs/WLB.12-unified-documentation.md) version 0.3.0 after DocShell
DSH.01 and Phoenix Assets PHA.01/PHA.02 provide their accepted packages. The cohort is
one commit of this repository (the packages under `packages/`, each extracted
in isolation, and the family tree under `docs/` with its root index) plus the
separate documentation-only `wotex-dot` source; HexDocs stays each package's
reference.

| Package | Status | Requires | Deliverable | Acceptance |
| --- | --- | --- | --- | --- |
| WLB-D01 | planned | DSH-P01/P02 | Explicit ecosystem catalogue, pinned/rolling cohort schemas and the package and source allowlist | WLB-V12-01/V12-02; catalogue schema and unknown-source failures |
| WLB-D02 | planned | WLB-D01; DSH-P01/P02 | Isolated per-package extraction runner for Mix packages and documentation-only sources | WLB-V12-02/V12-03; no Lab production dependency change |
| WLB-D03 | planned | WLB-D01/D02; DSH-P03/P04 | Wotex site projector, taxonomy, qualified routes, cross-package link resolver and source provenance | WLB-V12-04/V12-05 |
| WLB-D04 | planned | WLB-D03; DSH-P05; PHA-P08 | Unified section-aware Pagefind search, canonical search records and machine-document projection | WLB-V12-04/V12-07 |
| WLB-D05 | planned | WLB-D03/D04; PHA-P03–P09; PHA-U01–U10 | Public inert Workbench `/docs` routes, shared theme composition and bounded island enhancements | WLB-V12-06–V12-09/V12-13; no room/process side effects |
| WLB-D06 | planned | WLB-D03–D05; DSH-P07; PHA-P07 | Root/subpath static export, manifests, sitemap, robots, llms outputs and archive | WLB-V12-05/V12-06/V12-09/V12-12 |
| WLB-D07 | planned | WLB-D05/D06; DSH-P08; PHA-P10; PHA-U11–U13 | Browser, accessibility, visual, JavaScript-disabled, link, island and semantic parity cohort | WLB-V12-06–V12-10/V12-13 |
| WLB-D08 | planned | WLB-D05–D07; PHA-U11 | Static Storybook build, digest binding and collision-free composition at `/design-system/` | WLB-V12-13/V12-14 |
| WLB-D09 | planned | WLB-D01–D08 | Pinned release build, rolling resolver, reconciliation build, deployment preflight and fail-closed Pages workflow source | WLB-V12-10/V12-11/V12-14; pull requests never deploy |
| WLB-D10 | planned | WLB-D01–D09; WLB.08 | Fresh release/static consumers, archive inspection, provenance and qualification handoff | WLB-V12-01–V12-14 and WLB-C14 |

## Implementation layout

```text
priv/documentation/cohort.json
lib/wotex/lab/docs/catalogue.ex
lib/wotex/lab/docs/cohort.ex
lib/wotex/lab/docs/projector.ex
lib/wotex/lab/docs/link_resolver.ex
lib/wotex/lab/docs/search.ex
bin/build_documentation.exs
bin/check_documentation.exs
hosts/workbench/lib/wotex_lab_workbench_web/live/docs_live.ex
hosts/workbench/lib/wotex_lab_workbench_web/docs_theme.ex
hosts/workbench/test/.../docs_*.exs
hosts/workbench/bin/check_docs_browser.cjs
```

Names may change where the owning package already supplies the behavior. Lab
must not copy a DocShell collector, static exporter, or Phoenix Assets renderer
under these paths.

## Commit sequence

1. Catalogue and cohort validation.
2. Isolated extraction and failure evidence.
3. Site taxonomy, routes, links and provenance.
4. Search and machine-readable outputs.
5. Built-in Workbench pages.
6. Static export and archive checks.
7. Browser, accessibility, visual and parity evidence.
8. Static Storybook and combined artifact composition.
9. Rolling/release automation and deployment-source checks.
10. Fresh artifact evidence and qualification handoff.

Each group keeps its requirement/vector identifiers in executable tests and
fixtures. Generated HTML, search indexes and site output remain build artifacts
and are not committed as source.
