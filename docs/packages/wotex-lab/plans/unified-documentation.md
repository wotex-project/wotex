# Unified documentation implementation plan

This plan follows [WLB.12](../specs/WLB.12-unified-documentation.md) version
0.7.1. Its explicit cohort contains all twenty registered packages, each
extracted in isolation, the family documentation and the separate
`wotex-dot` governance source. HexDocs remains each package's reference.

Source implementation, current qualification and published adoption are
separate states. The published DocShell 1.0 collection API is selected. The
compact reader still needs a Phoenix Assets release that supplies inline
search and declares compatibility with DocShell 1.0. Source-candidate browser
results cannot close that dependency or renew historical artifact receipts.

| Package | Source | Deliverable | Qualification |
| --- | --- | --- | --- |
| WLB-D01 | implemented | Closed twenty-two-source catalogue, pinned/rolling resolution and explicit membership | Catalogue and workspace-graph regressions reject omissions, unknown sources and malformed identities; WLB-V12-01/V12-02. |
| WLB-D02 | implemented | Isolated package and documentation-only extraction, immutable checkout and source admission | Actual collection extraction renews each locked source digest; WLB-V12-02/V12-03. Runtime dependency closures are unchanged. |
| WLB-D03 | implemented | Site taxonomy, qualified routes, cross-collection links, API-member projection and provenance | Unit cases and the actual twenty-two-source projection cover WLB-V12-04/V12-05. Combined publication remains separate. |
| WLB-D04 | implemented | Pagefind index, canonical search records, seven facets, scope filters and machine documents | Real-index Elixir browser cases cover member search and all facets; WLB-V12-04/V12-07. |
| WLB-D05 | implemented | Inert Workbench documentation routes and compact Lab reader | Hosted/static candidate checks cover search, navigation and no room allocation. Published renderer adoption remains open; WLB-V12-06–V12-09/V12-13. |
| WLB-D06 | implemented | Shared root/subpath static export and manifested machine outputs | The complete candidate corpus renders 2,906 pages at both root and repository-subpath bases. Combined archive adoption remains separate; WLB-V12-05/V12-06/V12-09/V12-12. |
| WLB-D07 | partial | Browser, accessibility, visual, fallback and semantic parity acceptance | Six Elixir documentation journeys execute lazy search, keyboard, reflow, 400% zoom, theme, locale, 404 and no-JavaScript cases. Complete visual/accessibility and current artifact qualification remain open; WLB-V12-06–V12-10/V12-13. |
| WLB-D08 | implemented | Lab-owned static Storybook and collision-free publication composition | The component build and composition tests exist. The current combined artifact needs qualification; WLB-V12-13/V12-14. |
| WLB-D09 | implemented | Pinned release build, rolling resolver, preflight and fail-closed Pages workflow | Workflow source and isolated source checks exist. Public deployment is a maintainer action; WLB-V12-10/V12-11/V12-14. |
| WLB-D10 | implemented | Fresh archive/release consumers, inspection and provenance handoff | Historical receipts remain historical. The changed dependency cohort needs fresh full-host/static adoption; WLB-V12-01–V12-14 and WLB-C14. |

## Implementation layout

```text
priv/documentation/cohort.json
lib/wotex/lab/docs/catalogue.ex
lib/wotex/lab/docs/checkout.ex
lib/wotex/lab/docs/source_tree.ex
lib/wotex/lab/docs/staging.ex
lib/wotex/lab/docs/collection_builder.ex
lib/wotex/lab/docs/cohort_builder.ex
lib/wotex/lab/docs/cohort_resolver.ex
lib/wotex/lab/docs/projector.ex
hosts/workbench/lib/mix/tasks/wotex_lab.docs.build.ex
hosts/workbench/lib/wotex_lab_workbench/documentation/
hosts/workbench/lib/wotex_lab_workbench_web/documentation_live.ex
hosts/workbench/test/wotex_lab_workbench/documentation_*_test.exs
hosts/workbench/test/wotex_lab_workbench_web/documentation_live_test.exs
hosts/workbench/test/e2e/documentation_test.exs
bin/check_workbench_archive.exs
```

DocShell owns extraction, the portable model, indexing and static export.
Phoenix Assets owns its shared renderers. Lab owns membership, source
admission, product composition and publication; it does not copy either
producer's implementation.

## Remaining qualification

1. Adopt a published renderer with the required API and dependency range.
2. Qualify the combined twenty-two-source documentation and Storybook
   publication archive against the selected producer cohort.
3. Renew archive/release, SBOM, visual and accessibility receipts through their
   owning checks; preserve historical records until those checks succeed.
4. Hand the inspected artifacts and deployment preflight to the maintainer.
   Passing local checks neither deploys Pages nor establishes WCAG certification.

Generated HTML, indexes and site trees are build artifacts and stay outside Git.
