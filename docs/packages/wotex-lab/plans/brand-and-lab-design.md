# WoTEx brand and Lab design contract

Plan version: 1.10.0. Contract: accepted. Design status: under revision.
Owners: WoTEx family identity and WLB.11. Package path: `packages/wotex-lab`.

The programme includes a separate editable WoTEx brand identity file and an
editable Lab Workbench file with foundations, components, pages and task flows.
The design files are review and authoring deliverables. They do not establish
implemented browser behavior, Action authority or standards conformance.
WLB-C15 and WLB-C16 in the
[Lab completion contract](wotex-lab-completion.md)
own their acceptance. No package API or frontend framework changes here.

## Current review direction

The 2026-10-21 product review rejects the sidebar-led visual direction of the
existing Lab drafts. The [Canvas Workbench proposal](canvas-workbench.md) now
owns the proposed journeys: connect and inspect a system, ask and pin useful
measurements, run and explain an experiment, and read documentation with global
search. A full-page spatial canvas, floating icon tools and contextual
inspectors replace the previous page-led composition in this design review.
Documentation retains a separate, flat reading layout with a 48-pixel header.
The latest visual direction uses the supplied logo's cool grays, 14/16-pixel
icons, compact rows and at most two persistent workbench menu surfaces. Sections
and controls share 4-pixel corners; single-line buttons and fields are 28 pixels
high. Subtle shadows separate floating canvas elements, while documentation
stays flat. The board switcher is 38 pixels high with content-sized width and
four pixels after its arrow. The graph-paper background has reduced contrast.
Dark surfaces use a subdued `#444B5A` decorative border; focus and selection
retain their separate, stronger role.

The proposal is a review deliverable. Current source contracts, package APIs
and completion obligations remain unchanged until its behavior is reviewed and
promoted into their owning versions. The earlier editions below record bounded
historical authoring and prototype checks; they do not validate the rejected
product structure or qualify the new journeys. Preserve those frames as prior
drafts alongside the new proposal on separate journey pages. The identity
file retains those historical studies alongside the selected supplied mark.

## Design files and source authority

| File | Purpose | Current draft |
| --- | --- | --- |
| [WoTEx — Brand Identity](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0) | Family identity, guidelines and communication assets | Eight pages: Identity, Applications, Supplied studies, Artwork library and four preserved Archive pages. Includes the native usage Spec, eight-colour overview, twenty-one supplied application plates, thirty supplied study plates and thirty-two shared vector artwork masters. |
| [WoTEx Lab — Workbench](https://www.figma.com/design/SudxgeebiNEu33PPIHO229) | Lab system, prior references and proposed canvas journeys | Eight pages; sixty prior screen/state references, twenty-six canvas snapshots plus two theme reviews, twenty-nine documentation fixtures, seventy-seven current standalone targets, a compact component library and a current journey Spec on Start. Superseded page families are marked Archive. Current component and Play coverage are described in the canvas proposal. |

The initial edition was authored from repository commit
`b99ebe4bd121a2d071ab427502a247e3d8d3c8ad` and the source owners below.
Later source or design edits require a fresh comparison.

The Lab's [DesignSystem](../../../../packages/wotex-lab/lib/wotex/lab/design_system.ex)
owns semantic colour and geometry. Its
[token stylesheet](../../../../packages/wotex-lab/hosts/workbench/assets/components/tokens.css)
and [Button source](../../../../packages/wotex-lab/hosts/workbench/assets/components/button.svelte)
own the browser projection. Inter appears in the host font stack; system
fallbacks remain supported. The guide's type scale is a proposal rather than
a claim of exact CSS parity. The Lab's
[Workbench contract](../specs/WLB.11-workbench-and-design-system.md)
and [documentation contract](../specs/WLB.12-unified-documentation.md)
own product behavior. Source wins unless an explicit reviewed design change
updates those owners.

Keep the files separate and cross-linked. Use task names in the canvas, with
technical routes, source identities and content hashes in the external handoff.
Use editable text, native vectors, auto-layout, semantic variables and component
instances. A flattened screen image cannot satisfy a page deliverable. Preserve
designer proposals and stable node identities during later reconciliation.

## Brand identity acceptance

WLB-C15 requires the following delivered and reviewed contents:

- A selected identity direction, native default/inverse artwork, documented
  casing, lockups, permitted backgrounds, clear space, minimum sizes and misuse.
  Existing approved artwork takes precedence; a study is not approval.
- Exact digital colours, approved combinations, type roles, hierarchy and
  fallback guidance. UI semantic roles remain distinct from communication paint.
  Print colours remain unqualified until prepared and proofed.
- Layout, voice and imagery guidance, with a concise positioning statement and
  source/rights for imported assets. Claims distinguish software evidence from
  physical effects and certification.
- Useful native artwork and export presets for documentation, repository/social
  artwork and application icons, with actual destination dimensions, crop and
  contrast checks. Destination studies do not count as shipped assets.
- An asset handoff recording source-relative identity, hash, licence, native
  destination and approved treatment; a saved native archive and an independent
  restore check covering artwork, type, variables and component links.

The maintainer selected the supplied folded-W mark on 2026-10-21. Its exact
[SVG source](https://github.com/wotex-project/wotex/blob/e7fdfa4a078f28908f2394120a5c2b8701c9013d/docs/assets/brand/wotex-logo-light.svg) is retained with its
[asset notice](https://github.com/wotex-project/wotex/blob/e7fdfa4a078f28908f2394120a5c2b8701c9013d/docs/assets/brand/NOTICE); the native
[selected master](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=13-15)
preserves editable vectors and gradients. Use it without a surrounding tile or
box. The new Lab proposal takes its grayscale family from this artwork.
Earlier signatures, W tiles and blue/beige applications are historical studies.
The native [identity Spec](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=20-219)
now defines casing, permitted backgrounds, proposed sizes and clear space,
typography, voice, imagery and misuse. Product chrome uses the standalone mark;
no additional wordmark lockup is selected. The original mark remains unchanged.

The earlier Lab library edition added theme-aware instances of that default mark,
a derived treatment for dark surfaces and a solid monochrome treatment. The
derived artwork preserves the geometry; the dark treatment changes only its
two darkest gradient stops. These treatments are design proposals, not approval
of a replacement identity. The brand file now has matching native treatments
and a linked review sheet. The [asset handoff](https://github.com/wotex-project/wotex/blob/main/docs/assets/brand/exports/README.md)
contains three transparent SVGs, light/dark favicon and application PNG pairs,
and two social cards, with native source frames, hashes and destination sizes.
SVG path/viewBox checks and PNG integrity, transparency and crop checks passed;
light/dark icon pairs have identical alpha geometry. Native archive recovery
still requires independent restore evidence. These artwork checks do not
qualify browser installation or change application CSS. The supplied delivery
below is now authoritative for its default Light/Dark artwork; the earlier
derived dark treatment remains a proposal.

## Supplied identity programme

The maintainer's complete supplied delivery extends the selected folded-W
identity with eight colour, eight grayscale, eight flat, five construction and
one solid-ink study. The delivery selects Carbon Fold as its default and supplies
identical default artwork for Light and Dark surfaces. Both supplied default
SVGs have SHA-256
`d54dc6c57ffe432439763545ce970205e3f4145df3ceac12e74561bc6c7a996f`.
The earlier selected master is preserved; no inferred dark recolouring replaces
the supplied default.

The [Identity overview](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=43-252)
shows Carbon, Electric, Violet, Scarlet, Lagoon, Arctic, Solar and Spectrum,
each on Light and Dark surfaces. Sixteen instances reuse eight colour masters.
Product chrome continues to use the selected grayscale direction; having a
communication palette does not turn those colours into UI accents.

The [Applications page](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=34-252)
contains twenty-one supplied guideline plates. The
[Supplied studies page](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=34-253)
contains all thirty paired studies. They retain editable Inter text and native
vectors. Sixty artwork examples link to the
[Artwork library](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=37-252),
whose five component sets contain thirty-two unique masters. Byte-identical
Light/Dark sources share a master; different flat-carbon and solid-ink
treatments retain separate surface variants. Source-relative names and hashes
are recorded in component descriptions and the native identity Spec.

Native inspection confirmed thirty study sections, sixty linked examples and
no raster artwork. The eight-colour overview, palette plate and Electric Fold
pair were visually reviewed. These are supplied brand examples, not duplicated
Dark versions of entire product flows. Lab journeys continue to use shared
Light/Dark/Contrast variables, with two representative theme review frames.
A fresh native archive of the expanded brand file was saved and its ZIP
integrity checked. Independent restoration of its artwork, variables, type and
component links remains unverified.

## Lab pages, states and flows

The current [compact library](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=96-52)
adds seventeen core control/container families with eighty-four variants,
Light/Dark/Contrast semantic modes, seven Inter text roles, JetBrains Mono for
code and linked instance reviews. Sixteen connection and metrics storyboards
extend the initial fourteen proposal snapshots. Seventy-seven current standalone targets support
Thing-specific inspection, Ask/query/pin, three experiments, Action review,
command status, contextual reports and documentation. Before the documentation
addition, fifty-five of sixty-two targets were structurally reachable from the
explicit sample-room start; seven failure/expiry/denial alternatives remain
separate review fixtures. Five replaced helpers are hidden archives.
Native Play exercised pin pause/resume/removal and Smart room stage retention
through close/reopen, alongside the earlier inspection and metrics paths.
The documentation proposal has fifteen reusable content states across guide,
API, package, search/scopes and empty/error/missing cases. Native Play exercised
search/Enter, keyboard-selected API navigation, package detail and return to the
actual originating board with its metric pin preserved. Narrow navigation and
contents disclosures passed at 375 pixels. Representative Light/Dark/Contrast
articles were visually reviewed. Source-accurate experiment result
visualizations, full lifecycle/recovery and complete responsive/theme journeys
are still required; authored documentation alternatives do not establish live
search, clipboard or contents-scroll behavior.
These checks describe native design fixtures, not
implemented host behavior.

Descriptions and interaction rules now live in the native
[Canvas workbench journeys Spec](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=119-4210).
Its content was read through the managed Spec API, edited surgically and read
back after verification. The previous journey, layout and Start prose boards
are hidden; product frames retain task facts and controls.

The existing source exposes the six functional families below. WLB-C16 retains
their behavior and state coverage; the new proposal examines how those tasks
compose within a persistent workbench instead of giving each a thin page.
These route entries describe the current source, not the proposed navigation:

| Page family | Current entry | Required task and state coverage |
| --- | --- | --- |
| Experiments | `/` | Browse the three admitted experiments; explicitly start an isolated room; compose valid parameters; show validation, unavailable backend and denied scope |
| Run workspace | `/runs/:id` | Inspect source, shape/dtype, units, masks/quality, assertions and cleanup; running, complete, failed and cancelled states; inspect an inert proposal |
| Things | `/things` | Owned/empty lists, Thing Description and Interaction Affordances, explicit Property read, freshness, malformed input and unavailable transport |
| Metrics | `/metrics` | Bounded range/series/panels, units, gaps/loss/freshness, saved arrangements, empty/error states, data/table fallback and explicit exports |
| Evidence | `/evidence` | Exact run/query/source identity, conformance and formal-result scope, unavailable engine, bounded exports and session denial; optional investigation disclosure, cancellation and cited findings |
| Documentation | `/docs` and descendants | Search, navigation, contents, article/code/table reading, missing document and empty results; reading does not allocate a room |

Maintain named task-flow pages backed by the canonical references:

1. Start a room, select and run each admitted experiment, inspect the result and
   export its evidence. Include malformed parameters, failure and cancellation.
2. Review one exact smart-room Action scope, then cancel or explicitly approve.
   Bind the Thing, operation, input, proposal digest, decision revision and expiry.
   Include revoked/stale/expired decisions and transport/physical-effect limits.
3. Lose and restore a connection, refresh the current outcome and continue
   without replaying a run, prompt, export or approval. Preserve pending-command
   identity and unknown outcomes until authoritative evidence is available.
4. Inspect a Thing and bounded metrics, follow evidence, save a panel arrangement
   and export explicitly. Include loss, empty results and unavailable services.
5. Read documentation and, when configured, ask about a selected run after the
   data-destination disclosure. Ordinary operation remains complete without AI.

Each flow needs a concise adjacent brief with actor, goal, entry conditions,
ordinary outcome, alternatives, recovery and source links. Prefer native Figma
Specs when supported. Keep related prototype destinations on the same page,
with named starts and real back/cancel/recovery connections. A connected graph
is preparation; execute the named journeys in native Play before acceptance.

Cover compact, medium and expanded task containers using WLB.11's boundaries:
below 600, 600–839 and at least 840 pixels. Preserve subject/revision, drafts,
focus, evidence identity, units, missingness, approval scope and recovery.
Include Light, Dark and Contrast, keyboard/focus, loading, disconnected and
unavailable states. The boundary-pair browser checks remain executable source
obligations; static boards cannot satisfy them.

## Initial native edition and remaining acceptance

The 2026-10-21 edition contains native editable layers, forty-one variables
and six text styles in each file. Colour variables use Light/Dark/Contrast
aliases to primitives. The Workbench contains Button (twelve variants),
StatusBadge (four) and Field (four), with instance labels and token bindings.
This is a deliberately bounded projection, not the complete source component
catalogue. It contains illustrative data, not captured runtime results.

The [smart-room flow](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=5-6)
has experiment, running, result, approval, dispatch, cancellation, reconnect and
expiry references, plus medium/compact studies. Its three named prototype
starts are wired. The Things, Metrics, Evidence and Documentation references
cover the remaining page families, with compact empty/denied examples.
Native structural inspection found fifteen navigation reactions, with every
destination on the flow page, and semantic aliases in all three colour modes.
Screenshots were inspected for the brand boards, system controls, approval,
compact result and documentation. A palette-row overlap and compact navigation
wrapping were corrected during that review.

## Inspection and documentation journey edition

The continuation is source-bound to repository commit
`446007062681c56bbe3b30f5ae073994dfc20303`, with editable additions in the
existing Workbench file. It adds nineteen expanded screen/state references,
bringing the file to thirty-six. Panel, Primary navigation and Documentation
header are reusable native components; existing Button, Field and StatusBadge
families and the forty-one variables/six text styles are retained.

The [inspection journey](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=6-2)
connects an explicit Property read, bounded room telemetry, saved panel
definitions, a separate dataset-freeze action, dashboard export and the signed
session report. Unavailable-read, absent-measurement and denied-session paths
have recovery connections. Things no longer implies an Action at its Property
read boundary, and Metrics distinguishes session measurements from portable
instance-level panel definitions. A denied session returns to the empty-room
boundary rather than another room's evidence. The ordinary journey uses one
theme; the Panel review retains Light, Dark and Contrast specimens.

The [documentation journey](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=6-132)
connects a fixed search fixture, results and article reading. Its optional
owned-run branch shows the selected provider destination and bounded
sent/withheld content before Ask, then cancellation or illustrative findings
with cited evidence. Empty search, missing document and unavailable-provider
states preserve ordinary reading. No provider was contacted and no real export
was downloaded during prototype checks. Export checkpoints and the timed
answer are design fixtures, not new browser routes or executed host results.

Native Specs sit beside the
[run/approval/recovery](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=21-32),
[inspection](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=16-7)
and [documentation](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=22-251)
flows. Their content was read back through the native Spec API. Each names the
actor, goal, entry conditions, ordinary journey, alternatives, recovery,
acceptance and source permalinks. They preserve the remaining coverage and
authority limits rather than treating a connected graph as runtime evidence.

Structural inspection found fifty-four inspection and thirty-four documentation
frame-target reactions, all targeting frames on their own page, plus one
history-based return from cited evidence. That return preserves its originating
task rather than showing an answer after cancellation or without a provider.
Their UI layers
are native text, frames and component instances, with no image fills, no text
outside the frame bounds and the selected Inter draft font. Representative
full-view renders were reviewed. A hidden Panel surface fill was corrected
after it made Dark/Contrast text unreadable; the three-theme review then passed.

Native Play exercised the inspection journey through read, metrics, arrangement
save, dashboard export and report export, plus return navigation and dataset
freeze. It also exercised documentation search, article reading, selected-run
disclosure, investigation cancellation, timed illustrative findings and their
run/query citation. The unavailable-provider branch also opens ordinary evidence
and returns to its disabled composer without showing an unrequested answer.
These are native prototype checks,
not Workbench browser, provider, export-content or authority qualification.

## Admitted experiments and numerical result edition

This continuation is source-bound to repository commit
`aef8906422d59e5ed4f4a697ec790c6a137209f5`. It adds twenty-four editable
screen/state references and extends the existing experiment page, bringing the
Workbench file to sixty. The new ExperimentCard family has the three admitted
experiment variants; ParameterField composes the existing Field with its label
and type/bounds help. No variables, text styles, package APIs, routes or backend
selections change.

The [experiment entry](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=39-32)
shows all three admitted forms before any numerical result: one thermal,
six window-anomaly and four smart-room controls, with their source defaults and
bounds. Browsing starts no room. An explicit room-start action starts no
experiment; an explicit Run may also allocate its room, as the host permits.
Long forms use native vertical scrolling rather than dropping controls.
The catalogue continues into the existing smart-room proposal/approval flow
and new thermal/anomaly pending, result and selected-evidence references.

The [thermal result](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=39-350)
puts backend, shape/dtype, units, masks and quality before the encoded values.
The two Kelvin observations, Celsius values and inert 22.0 Cel target follow
the checked-in source example. The anomaly window and score are hand-authored
design fixtures, explicitly not a realized output of simulator seed 1.
No numerical runner or model was executed to author this edition. Both result
views retain assertions, cleanup, inert-output scope and illustrative run
identity; they do not substitute invented runtime digests for evidence.

The same thermal result, selected evidence and report-return path has expanded
(1280), medium (720) and compact (390) references. Native structural comparison
confirmed identical thermal subject, result and support-panel content across
the three widths. Compact content scrolls in semantic order. This is native
design comparison, not the executable 599/600 or 839/840 browser boundary gate.

Refusal references cover Samples 513 at `/count`, an unavailable selected
backend without fallback, numerical failure, guest policy refusal, session
denial and failed room startup. Parameter refusal retains all six anomaly
controls and disables the rejected Run hotspot. Failed and denied runs have
their own evidence identities and outcomes. Evidence and shared report returns
use actual navigation history so a failure or refused proposal cannot return
as a successful granted run. The native experiment Spec was updated and its
content read back without replacing the document.

Structural inspection found sixty-seven frame-target navigation reactions and
ten history returns on the experiment page, with no missing, cross-page or
self-target destinations. Its UI uses native text, frames and component
instances, no image fills and no horizontal text overflow. The three-card
specimen and representative expanded/compact/result/refusal viewport renders
were visually inspected. Vertical clipping is intentional only at the declared
scroll viewport; full controls and supporting evidence remain in its content.

Native Play exercised room startup, thermal and anomaly submission through
their illustrative results, and selected evidence/report/history returns for
all three experiments. It also exercised smart-room approval return, explicit
prototype dispatch and pending-run cancellation. A selected-run identity
mismatch was corrected between the smart-room proposal and evidence; the
corrected identity was verified in Play. Its illustrative pending timer was
lengthened to keep cancellation usable; this is no runtime latency claim.

The failed-run and guest-refusal starts each reached their own evidence,
export checkpoint and original outcome through history returns. The rejected
anomaly form retained all six controls while scrolling, its disabled Run did
not navigate, and explicit correction returned to the ready catalogue without
starting a run. The compact thermal journey reached cleanup, selected evidence
and report export, then returned through the same compact task. No real room,
numerical run, Action, provider call or file download occurred in these checks.
The review below covers the medium result and backend, session and room-start
recovery paths. Their connected graph alone did not qualify them.

## Medium task and recovery review

The 2026-10-21 review at repository commit
`222ffc08124b472e613a139a023b667d1726d9be`, package `packages/wotex-lab`,
exercised these existing references in native Play:

| Start | Executed journey and observed outcome |
| --- | --- |
| [Medium thermal result](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=39-376) | The 720-pixel result opened its selected evidence and explicit report checkpoint, then returned through the evidence to the result. Each retained `thermal-design-01`; dtype, dimensions, Cel units, values, masks, quality and the inert proposal remained visible. |
| [Unavailable backend](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=39-457) | The refusal named the selected binary backend and prohibited implicit fallback. Back returned to the ready catalogue without entering a running or result state. |
| [Denied session](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=39-518) | New session returned to the no-room catalogue, with explicit startup and no previous room or run. |
| [Failed room startup](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=39-537) | Explicit retry reached the ready catalogue; Return to catalogue reached the no-room state. Neither entered an experiment. |

The denied-session and failed-start navigation instances now say
“Session unavailable / No room access” and “No ready room / Startup failed”,
respectively. This corrects the generic “Session-owned room” footer that
contradicted both recovery states. The existing components, semantic colour
bindings and frame identities are retained; the medium named start is available
in Play. The two corrected screens were visually inspected after their edits.

These checks exercise fixed prototype states and navigation. They executed no
room startup, numerical runner, backend fallback, Action, provider request or
report download. The single medium journey does not qualify all component,
theme and container combinations. Reconnect/unknown-outcome, revoked/stale/
expired approval journeys, native archives and independent restores remain
acceptance work.

## Brand artwork and channel edition

The brand continuation retains the existing typographic direction and adds
three reusable draft families: nine Name/Descriptor/Lab treatments, three
Letter W tile studies and two repository preview compositions. Three native
review boards show the treatments, proposed spacing/minimum widths, actual-size
small icons and channel layouts. Fixed artwork roles alias the existing palette
independently of Lab UI modes; the brand file now has fifty-two variables and
eight text styles. No implemented CSS projection or Workbench asset changes.

The [draft artwork handoff](../provenance/brand-artwork-2026-10.md) records the
source baseline, native IDs, proposed treatments, attribution and SHA-256 of
twelve SVG and eleven PNG exports. Native rendering and local artifact checks
cover editable layers, selected Inter fonts, bounds, outlined SVG paths, PNG
integrity/dimensions/transparency, solid colour contrast and repository-preview
size. The two 1280 × 640 PNG previews are below 1 MB. No destination setting
was changed; the draft exports live under `docs/assets/brand/draft/`.

These additions made the earlier identity proposal concrete for review. The
supplied mark selected above supersedes its mark studies. Approved usage rules,
recognition, co-branding, print preparation, destination adoption and native
archive/restore acceptance remain required.

The full component catalogue, all page/state/profile combinations, remaining
native Play journeys, final brand acceptance, channel artwork, native archives
and independent restores are still acceptance obligations.
The current files have not been published as libraries, and folder placement
or collaborator access has not been qualified. Design completion and browser
implementation evidence must be recorded separately. Historical WLB.11 evidence
manifests remain unchanged; they do not prove this new design edition.
