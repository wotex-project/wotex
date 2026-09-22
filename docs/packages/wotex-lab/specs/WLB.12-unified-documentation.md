# WLB.12: Unified ecosystem documentation

Specification version: 0.3.2. Contract: accepted. Implementation status:
implemented. Evidence status: complete. Adoption status: reference_available.

## Implemented source and evidence boundary

Lab now owns the validated source catalogue, isolated checkout and staging
rules, release and rolling cohort resolution, collection admission and the
single route/taxonomy projector. The Workbench builds that model with the
pinned DocShell and Phoenix Assets contracts, serves inert LiveView routes and
the same generated Pagefind tree, and exports the same page model as a static
site. The combined publication stage admits separately manifested DocShell and
Storybook trees only after link, asset, collision and design-contract checks.
The release task accepts an explicit local source for every admitted repository;
its offline mode refuses an incomplete set before checkout, so a distribution
build cannot silently replace a missing input with network access.

Focused unit, LiveView, publication, archive and real-Chromium cohorts cover
the declared source types, exact digests, route projection, all Pagefind
filters, live/static parity, keyboard use, 320-pixel reflow, 400% zoom, themes,
high contrast, reduced motion, left-to-right and right-to-left locales,
JavaScript-disabled fallbacks, 404 behavior and blocked network access. The
clone-free release gate builds DocShell and Phoenix Assets candidate archives,
resolves them through a local Hex registry, embeds the generated site and
search tree, removes Git from the release environment and reads both from the
release.

This is complete local source and candidate-artifact evidence. It is not a
successful GitHub Pages deployment, a public-site availability claim or a WCAG
certification. Those adoption checks remain in the qualification runbook and
never authorize a repository visibility change.

## Purpose

Wotex Lab owns one documentation catalogue for the complete Wotex ecosystem.
The Workbench serves it as public LiveView pages, and the documentation build
exports the same corpus and presentation as a static site. Package Markdown,
module documentation, Livebooks, specifications, and machine-readable API
descriptions remain authoritative where they are maintained: package sources
under `packages/<name>/`, specifications, plans, decisions and provenance under
`docs/packages/<name>/`, family documents under `docs/`, and project governance
in `wotex-dot`.

The aggregate is generated. Maintainers do not copy source documents into Lab,
rewrite the same guide for a second site, or maintain navigation separately in
the LiveView and static outputs.

This contract consumes DocShell's DSH.01 portable-site contract and Phoenix
Assets' PHA.01 LiveView/static renderer contract. Lab owns Wotex source
membership, taxonomy, branding, theme, product components, optional islands,
public routes, release profiles, domain composition and deployment evidence.

## Source cohort

The catalogue has an explicit allowlist of sources taken from one commit of
this repository, plus the separate `wotex-dot` source. A directory under
`packages/` or a name beginning with `wotex` does not grant membership.

| Area | Source |
| --- | --- |
| Core model | `wotex` |
| Runtime | `wotex-runtime` |
| Binding templates | `wotex-binding-http`, `wotex-binding-mqtt` |
| Protocol bindings | `wotex-modbus`, `wotex-coap`, `wotex-bacnet`, `wotex-opcua`, `wotex-ble`, `wotex-matter`, `wotex-thread` |
| Discovery and exchange | `wotex-directory`, `wotex-continuum` |
| Numerical computing | `wotex-nx` |
| Conformance | `wotex-conformance` |
| Laboratory | `wotex-lab` |
| Family documentation | `docs/` outside `docs/packages/`: the root index `docs/README.md`, architecture and guides |
| Project governance | `wotex-dot` |

Every row except the last two names a package under `packages/`.
`packages/wotex-lab/priv/documentation/cohort.json` describes each member with
source ID, title, repository URL and path, source kind, Hex package name when
present, documentation roots, default branch for the rolling profile, exact
revision and tree digest for a pinned profile, license, build command, and
expected DocShell artifact digest. A package's documentation roots are its
directory `packages/<name>/` and `docs/packages/<name>/` (`specs/`, `plans/`,
`decisions/`, `provenance/` and package-level documents); its tree digest
covers those paths at the recorded revision. Unknown keys and sources fail
validation.

The family documentation tree and `wotex-dot` are documentation-only sources.
They have no Mix application and are collected through the same Markdown
extractor with an empty module set.

## Source generation

Each package is extracted in an isolated work directory with its own lock and
toolchain lane. A package runs `mix doc_shell.build --no-start` in
`packages/<name>/` against its compiled documentation chunks and its
allowlisted document roots. A documentation-only source runs the DocShell build
API from the collector without starting an application.

Every package declares DocShell as a build-only dependency for its `dev`,
`test` and `docs` environments and supplies a site-ready collection identity.
`collection.json` binds the exact repository revision and the source's tree
digest, repository-relative sources, extracted module documentation and
artifact content digest. The central builder does not inject code or
configuration into a package or a source checkout.

The collector never adds the protocol packages as production dependencies of
`wotex_lab` or the Workbench. It does not load all applications into one BEAM
instance. This prevents documentation generation from selecting a combined
runtime dependency closure that none of the libraries supports.

An extracted collection includes:

- public module and member documentation;
- the package `README.md`, allowlisted package-level documents and family
  guides;
- `docs/packages/<name>/specs/`, `decisions/` and `plans/`;
- public provenance and standards notes under `docs/packages/<name>/provenance/`;
- runnable `.livemd` notebooks;
- generated OpenAPI or other admitted interface documents; and
- release notes as history content, outside the primary task-oriented
  navigation.

Local task state, credentials, build output, dependencies, private notes,
machine paths, and files outside the allowlist never enter a collection.
`docs/tasks/local/` is excluded before parsing and remains excluded from every
manifest and package.

Every source document retains source ID, exact repository revision,
repository-relative path, content digest, license, and an immutable source
URL. An edit link targets the configured editable branch only when the page
profile permits it; source identity still names the exact rendered revision.

## Build profiles and freshness

The documentation builder supports two profiles:

1. `release` reads exact revisions and digests committed in the cohort file.
   The resulting built-in documentation is coherent with that Lab release.
2. `rolling` resolves the configured default-branch heads of this repository
   and `wotex-dot` once at the start of an automated build, records those
   immutable revisions, checks out exactly those revisions, and writes the
   resolved cohort into the site manifest. It never reads a moving branch after
   resolution.

A default-branch push that changes a cohort source triggers the rolling build.
A scheduled reconciliation catches missed triggers and changes to `wotex-dot`.
Pages settings and any deployment credential are operator-managed repository
configuration. They are not stored in source. If a source cannot be resolved,
extracted, validated, or rendered, publication stops and the last complete site
remains deployed.

“Current” means the exact cohort disclosed by the site, not an unrecorded mix
of package states or branch heads. The site exposes cohort digest, generation time, source
revision, and profile. A rolling site reports when a later known build failed;
it does not silently label the retained cohort as newly generated.

## Information architecture

The primary navigation is task and concept oriented:

```text
Start
Concepts
Core Thing Description
Runtime
Bindings
  HTTP
  MQTT
Protocols
  Modbus
  CoAP
  BACnet
  OPC UA
  Bluetooth LE
  Matter
  Thread
Discovery and exchange
Numerical computing
Conformance
Lab and workbench
API reference
Specifications and evidence
Project and contribution
```

Package and source names remain visible as provenance and search filters.
They do not form one unrelated top-level documentation site per package. Each protocol section
places its overview, addressing, WoT Form mapping, lifecycle, structured
errors, examples, interoperability profile, API reference, specifications, and
evidence in a consistent order.

Navigation rules live in one Lab projector. A source page can supply title,
description, ordering, tags, status, locale, audience, sidebar label, and
visibility metadata. It cannot place another package or source into the
cohort or override an unrelated section.

## Routes and links

The Workbench serves public inert routes below `/docs`. They allocate no Lab
room, start no experiment, perform no protocol I/O, and require no LLM,
GreptimeDB, broker, or device.

Canonical route families are:

```text
/docs/start/
/docs/concepts/<page>/
/docs/runtime/<page>/
/docs/bindings/<binding>/<page>/
/docs/protocols/<protocol>/<page>/
/docs/discovery/<page>/
/docs/numerical/<page>/
/docs/conformance/<page>/
/docs/lab/<page>/
/docs/api/<package>/<module>/
/docs/specifications/<package>/<spec>/
/docs/evidence/<package>/<record>/
/docs/project/<page>/
```

The static exporter supports both a domain root and a GitHub Pages repository
subpath from the same route model. Internal repository-relative links are
resolved to canonical aggregate routes when their target belongs to the
cohort. Unknown local targets, anchors, and assets fail the build. External
standards links remain external and identify their source revision where the
owning specification requires it.

Legacy package documentation URLs may redirect to canonical aggregate routes
only through an explicit, tested redirect map. HexDocs remains each package's
automatically published reference and fallback, and `docs/README.md` remains
the in-repository index; Wotex READMEs use the aggregate site as their primary
documentation link when the public site is available.

## LiveView and static presentation

The Workbench consumes `PhoenixAssets.DocShell` components. Lab provides theme
tokens, product composition, logo/title slots, section taxonomy, source links,
and routes. It does not fork the AST, API reference, search, navigation, code,
diagram, or content directive renderers.

The Phoenix Assets renderer carries only renderer-scoped controls and CSS.
Lab wraps it with the Wotex design contract and owns every product-level
component, theme and Storybook fixture. Renderer internals remain in Phoenix
Assets; Workbench semantics and branding do not move there.

The static build invokes the same HEEx components through
`PhoenixAssets.DocShell.StaticRenderer`. The LiveView may add transport
attributes, but both outputs share the same DocShell site/page values, CSS,
browser entry, assets, route graph, search corpus, visible content, headings,
links, and accessible names.

The LiveView route may mount a registered Svelte island for an interaction that
benefits from local client state. The island follows WLB.11's Lab-owned
single-owner DOM, bounded prop/event, revision, resynchronization, fallback and
teardown rules.
Article text, navigation, search fallback, source provenance and ordinary links
do not depend on an island or LiveSocket. The static export includes no enabled
server-backed control and requires no endpoint, WebSocket or Node process.

The default documentation shell includes keyboard search, hierarchical and
collapsible navigation, breadcrumbs, table of contents, previous/next flow,
source and edit links, last-updated/source-revision context, version/status
badges, light/dark/system themes, code copy and highlighting, Mermaid diagrams,
OpenAPI reference, locale and direction support, and useful no-JavaScript
fallbacks.

The visual quality target is a modern technical documentation product:
carefully measured typography, restrained semantic color, consistent vertical
rhythm, responsive navigation, stable code/table overflow, clear current-page
state, and empty/error/404 pages that preserve navigation and search. It does
not reproduce another project's brand or require an external font, icon, CSS,
script, analytics, or search service.

## Design-system publication

The documentation build also publishes the Wotex Lab Svelte Storybook at
`/design-system/` unless the host selects a separate origin. This is the public
static component catalogue for the primitives, islands and reporting
components used by the Workbench. It imports the production Svelte modules,
CSS and fixed story fixtures from Lab.

The Storybook build and DocShell site are separate manifested trees combined by
one publication step. Their routes and assets cannot collide. The deployment
records the Wotex Lab host/npm versions, token digest, component registry
digest, story fixture digest and Storybook output digest. A failed
catalogue build leaves the preceding complete documentation publication in
place.

Storybook mock transports demonstrate component presentation and failure
states. They do not claim LiveView authorization, persistence, reconnect or
effect execution. A separately deployed Phoenix Storybook reference host may
provide real LiveView examples. It is not part of the static Pages artifact,
and the public docs remain complete when it is absent.

## Search and machine interfaces

One search corpus covers guide pages, headings, module/member documentation,
specifications, decisions, evidence summaries, notebooks, and API operations.
Results can be filtered by package or source, section, document kind,
protocol, version, locale, status, and audience. The browser performs ordinary
search without a server or account.

The Wotex public and built-in profiles select Phoenix Assets' pinned Pagefind
adapter. It produces section-level, chunked static indexes and loads them on
first search use. The Workbench serves the same generated Pagefind directory as
the static site, so LiveView does not introduce a separate server-side ranking
algorithm. `search-records.json` retains the canonical DocShell records for
machine consumers and parity checks.

The static tree also contains:

- `site-manifest.json` with routes, files, digests, renderer and cohort;
- `search-records.json` and the manifested Pagefind directory;
- `sitemap.xml` and `robots.txt`;
- `llms.txt` as a concise route/source index;
- `llms-full.txt` as the bounded public textual corpus; and
- Lab's existing graph representations linked from the relevant evidence page.

These files are generated from the same accepted pages. A separate hand-edited
machine corpus is forbidden.

## Publication

The public output is an ordinary static directory. The reference deployment is
GitHub Pages through a custom Actions workflow because public repositories can
use Pages without a hosting charge. The build and deploy jobs are separate.
Pull requests build and retain the artifact without deploying. Only the
configured default branch can deploy.

Actions use immutable revisions. The build job has read-only repository
permissions and no Pages write permission. The deployment job receives only
the validated static artifact and the minimum `pages: write` and
`id-token: write` permissions. Publication creates no source commit and does
not use a generated branch as the documentation source.

Custom-domain and repository-visibility settings remain manual maintainer
actions. The implementation and tests must work at the default GitHub Pages URL
without either change.

## Accessibility, performance and offline behavior

The documentation surface targets WCAG 2.2 AA with semantic landmarks, skip
navigation, visible focus, keyboard operation, labelled dialogs and controls,
focus restoration, contrast, reduced motion, reflow, zoom, locale language and
direction, text status, and code/diagram fallbacks. Automated checks support
review and do not claim certification.

The normal article path loads no Mermaid or API request code until the page
needs it. Search loads on first use. CSS, browser core, search, highlighting,
Mermaid, and API assets have separate compressed and uncompressed budgets.
Pages render their complete article and navigation before enhancement.

A downloaded static artifact works from a local HTTP server with network access
blocked. The built-in Workbench route works with the same source corpus after
the release is disconnected from GitHub. Runtime never fetches repository
content or documentation dependencies.

## Requirement catalogue

| ID | Requirement |
| --- | --- |
| WLB-S12-01 | Maintain one explicit allowlist and taxonomy for every Wotex package, the family documentation tree and the documentation-only project source. |
| WLB-S12-02 | Require each package to expose a site-ready DocShell build and generate every corpus in isolation without adding protocol packages to Lab's production dependency graph. |
| WLB-S12-03 | Bind every page and site generation to exact source revisions, tree/content digests, package versions, paths, and licenses. |
| WLB-S12-04 | Generate one validated navigation, route, link, search, machine-interface, and provenance model for the whole cohort. |
| WLB-S12-05 | Serve public inert `/docs` LiveView routes without allocating Lab runtime state or requiring optional operational services. |
| WLB-S12-06 | Export the same site/page model through the shared Phoenix Assets HEEx renderer as a complete static site. |
| WLB-S12-07 | Provide the specified modern documentation capabilities, responsive behavior, accessibility target, and no-JavaScript fallbacks. |
| WLB-S12-08 | Support pinned release and automatically resolved rolling profiles without publishing a partial or undisclosed cohort. |
| WLB-S12-09 | Build and validate a provider-neutral static artifact and a fail-closed GitHub Pages workflow with no paid service dependency. Remote deployment follows the WLB.08 qualification runbook. |
| WLB-S12-10 | Keep source documents authoritative where they are maintained and reject copied, private, unallowlisted, unresolved, or stale aggregate inputs. |
| WLB-S12-11 | Apply one Lab-owned design-system contract to Workbench, LiveView docs, static docs and Storybook, with Svelte islands confined to explicit progressive-enhancement boundaries. |
| WLB-S12-12 | Build the production Svelte component catalogue as a separately manifested static Storybook while keeping live-only examples in an optional isolated Phoenix host. |

## Executable vectors

| ID | Evidence |
| --- | --- |
| WLB-V12-01 | The catalogue includes every source in the accepted cohort exactly once and rejects a glob-discovered or unknown source, including an unlisted directory under `packages/`. |
| WLB-V12-02 | Every package, the family documentation tree and `wotex-dot` emit a valid isolated DocShell collection with exact revision/tree/artifact digests. |
| WLB-V12-03 | A dependency conflict between two packages does not affect collection because their builds use separate work directories and BEAM instances. |
| WLB-V12-04 | All admitted Markdown, modules, members, notebooks, specifications, decisions, provenance and APIs appear once or have an explicit exclusion. |
| WLB-V12-05 | Cross-package links (between `packages/` and `docs/`), anchors, assets, canonical routes, source links and edit links resolve at `/docs` and a configured Pages subpath. |
| WLB-V12-06 | LiveView and static pages share cohort/page digests, visible text, navigation, headings, links, search records and accessible names. |
| WLB-V12-07 | The shared Pagefind index finds fixed guide, module member, protocol, specification, evidence, notebook and API-operation queries, applies every declared filter, and lazy-loads index chunks in both hosts. |
| WLB-V12-08 | Browser tests cover keyboard search/navigation, mobile/desktop layouts, 400% zoom, themes, reduced motion, left-to-right/right-to-left, JavaScript disabled and 404 behavior. |
| WLB-V12-09 | Static output has no remote runtime asset or hosted-service call, obeys bundle budgets, and works with network blocked. |
| WLB-V12-10 | A failed source, extraction, validation, render, link, accessibility, asset-budget or deployment preflight leaves the prior published artifact intact. |
| WLB-V12-11 | The release profile reproduces its payload from the committed cohort; the rolling profile records one resolved immutable cohort and detects a missed trigger by reconciliation. |
| WLB-V12-12 | A fresh Workbench release serves built-in docs with Git unavailable and no source checkout; a fresh static archive serves from a local HTTP server. |
| WLB-V12-13 | Workbench, LiveView docs, static docs and Storybook report the same Lab token, CSS, component-registry and fixture digests; Phoenix Assets contains no product component catalogue. |
| WLB-V12-14 | The combined static artifact serves docs and `/design-system/` from a local HTTP server below root and repository subpaths, contains no route/asset collision or live socket URL, and retains the prior complete staged output when either build fails. |

## Evidence boundary

WLB.12 is complete only after DSH.01 and PHA.01 artifact versions are
pinned and WLB-S12-01 through WLB-S12-12 have executable source or
candidate-artifact evidence. A local workspace build is source evidence. A Pages
workflow file is deployment-source evidence. A successful default-branch
deployment with a recorded artifact and URL is hosted adoption evidence under
the [qualification runbook](../plans/qualification.md); it does not decide
WLB.12 implementation status. None changes repository visibility or publishes a
package.
