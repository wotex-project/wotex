# Unified documentation implementation plan

This tracker implements
[WLB.12](../specs/WLB.12-unified-documentation.md) after DocShell DSH.01 and
Phoenix Assets PHA.01 provide their accepted packages.

| Package | Status | Requires | Deliverable | Acceptance |
| --- | --- | --- | --- | --- |
| WLB-D01 | planned | DSH-P01/P02 | Explicit ecosystem catalogue, pinned/rolling cohort schemas and repository allowlists | WLB-V12-01/V12-02; catalogue schema and unknown-source failures |
| WLB-D02 | planned | WLB-D01; DSH-P01/P02 | Isolated per-repository extraction runner for Mix and documentation-only sources | WLB-V12-02/V12-03; no Lab production dependency change |
| WLB-D03 | planned | WLB-D01/D02; DSH-P03/P04 | Wotex site projector, taxonomy, qualified routes, cross-repository link resolver and source provenance | WLB-V12-04/V12-05 |
| WLB-D04 | planned | WLB-D03; DSH-P05; PHA-P08 | Unified section-aware Pagefind search, canonical search records and machine-document projection | WLB-V12-04/V12-07 |
| WLB-D05 | planned | WLB-D03/D04; PHA-P03–P09 | Public inert Workbench `/docs` routes and Wotex theme composition | WLB-V12-06–V12-09; no room/process side effects |
| WLB-D06 | planned | WLB-D03–D05; DSH-P07; PHA-P07 | Root/subpath static export, manifests, sitemap, robots, llms outputs and archive | WLB-V12-05/V12-06/V12-09/V12-12 |
| WLB-D07 | planned | WLB-D05/D06; DSH-P08; PHA-P10 | Browser, accessibility, visual, JavaScript-disabled, link and semantic parity cohort | WLB-V12-06–V12-10 |
| WLB-D08 | planned | WLB-D01–D07 | Pinned release build, rolling resolver, dispatch/reconciliation build and fail-closed Pages workflow | WLB-V12-10/V12-11; pull requests never deploy |
| WLB-D09 | planned | WLB-D01–D08; WLB.08 | Fresh release/static consumers, archive inspection, provenance and hosted adoption record | WLB-V12-01–V12-12 and WLB-C14 |

## Implementation layout

```text
docs/documentation/cohort.json
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
8. Rolling/release automation and deployment-source checks.
9. Fresh artifact and hosted-adoption evidence.

Each group keeps its requirement/vector identifiers in executable tests and
fixtures. Generated HTML, search indexes and site output remain build artifacts
and are not committed as source.
