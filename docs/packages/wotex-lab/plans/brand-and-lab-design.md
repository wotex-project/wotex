# WoTEx brand and Lab design contract

Plan version: 1.0.0. Contract: accepted. Design status: partial.
Owners: WoTEx family identity and WLB.11. Package path: `packages/wotex-lab`.

The programme includes a separate editable WoTEx brand identity file and an
editable Lab Workbench file with foundations, components, pages and task flows.
The design files are review and authoring deliverables. They do not establish
implemented browser behavior, Action authority or standards conformance.
WLB-C15 and WLB-C16 in the
[Lab completion contract](wotex-lab-completion.md)
own their acceptance. No package API or frontend framework changes here.

## Design files and source authority

| File | Purpose | Initial edition |
| --- | --- | --- |
| [WoTEx — Brand Identity](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0) | Family identity, guidelines and communication assets | Four pages; five guideline boards and one editable signature component |
| [WoTEx Lab — Workbench](https://www.figma.com/design/SudxgeebiNEu33PPIHO229) | Lab system, canonical page references and connected task flows | Five pages; seventeen screen/state references, three component families and three named prototype starts |

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

The current identity file is a draft. The implemented warm-light and rich-navy
palette is retained. The editable typographic signature, communication copy and
application layouts are proposals. Final mark selection, spacing/size rules,
channel exports, final voice and recovery acceptance remain required work.

## Lab pages, states and flows

WLB-C16 requires canonical editable designs for all six page families, aligned
with current routes rather than a new route catalogue:

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

The full component catalogue, all page/state/profile combinations, adjacent
native Specs, native Play journeys, final brand acceptance, channel artwork,
native archives and independent restores are still acceptance obligations.
The current files have not been published as libraries, and folder placement
or collaborator access has not been qualified. Design completion and browser
implementation evidence must be recorded separately. Historical WLB.11 evidence
manifests remain unchanged; they do not prove this new design edition.
