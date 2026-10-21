# Canvas Workbench: journeys and design proposal

Plan version: 0.2.0. Status: proposed for design review. Implementation: not
started. Owners: WLB.11 and WLB.12. Package: `packages/wotex-lab`.

The Lab becomes a persistent spatial workbench for understanding a connected
system, investigating measurements and running experiments. A full-page canvas
holds Things, their typed connections and user-pinned results. Compact floating
tools and contextual inspectors support the current journey. Documentation has
its own conventional reading layout and global search.

This proposal replaces the visual direction of the previous sidebar-led Figma
drafts. It does not claim that the new canvas, live Thing subscriptions or
prompt-to-pin protocol exist. Existing package contracts remain authoritative
until the reviewed proposal is promoted into their versioned obligations.
The [design contract](brand-and-lab-design.md) retains identity and native-file
acceptance; [WLB.11](../specs/WLB.11-workbench-and-design-system.md) owns frontend
behavior and [WLB.12](../specs/WLB.12-unified-documentation.md) owns documentation.

## Product model and workspace

The primary user is an engineer asking: what is connected, what is happening,
why did it happen, and what should I inspect or run next? Opening the Lab shows
the current workbench. It does not make the user choose between a catalogue of
thin feature pages.

| Surface | Role in a journey |
| --- | --- |
| Spatial canvas | Persistent topology, selected subjects, pinned charts and results; pan, zoom, fit and arrange locally |
| Floating board control | Supplied unboxed logo and compact board dropdown; room/source status, counts and saved-layout state live in its menu |
| Floating icon palette | One narrow tool rail; select/pan and grouped tools expose search, connect, metrics/Ask, experiments, activity, documentation and viewport controls through submenus |
| Context menu | Operations for the selected Thing, connection, metric pin or run; opened by right-click, ellipsis or keyboard |
| Right inspector | Properties, metrics, configuration, run detail or query result for the selected subject; close restores its canvas context |
| Bounded dialog | Import/connection setup, naming, export options or review of an exact proposed Action |
| Documentation | Searchable article layout with its own navigation and a return to the workbench |

The canvas has at most two persistent compact menu surfaces: board control and
tool rail. Search/status and zoom do not occupy separate floating bars. Use
16-pixel tool icons, 14-pixel menu/node icons, 28-pixel desktop targets and menu
rows, 12-pixel labels and 14-pixel inspector titles. The rail is 36 pixels wide;
context menus start at 200 pixels. Touch and zoomed layouts need their own
composition. These are design proposals, not current CSS or accessibility
qualification.

The workbench background follows the supplied graph-paper reference: a fine
6.5-pixel mesh, secondary lines every 26 pixels and crosshairs every 104 pixels.
The [repeating SVG tile](https://github.com/wotex-project/wotex/blob/4ca9541c864f31b0739d08b0bcb3ad893897f61d/docs/assets/lab/workbench-grid.svg)
is 650 bytes, with no raster, font, script or external resource. It replaces the
earlier dot grid. Keep its origin consistent with canvas pan/zoom during
implementation; opaque data surfaces sit above it.

Icon artwork comes from Lucide revision
`20aef31db93fe4d9f398dbb15b120d99c48eef95`. The source SVGs and upstream
[license](https://github.com/wotex-project/wotex/blob/e7fdfa4a078f28908f2394120a5c2b8701c9013d/docs/assets/icons/lucide/LICENSE) are retained with their
[notice](https://github.com/wotex-project/wotex/blob/e7fdfa4a078f28908f2394120a5c2b8701c9013d/docs/assets/icons/lucide/NOTICE). This supplies design artwork;
it does not add a frontend dependency or change the implemented Icon component.

Use Inter and the supplied logo's cool grays: `#181D27`, `#303644`, `#818A9D`,
`#9097A5` and `#D6DBE3`, with white and pale surface tints. Selected controls,
edges, charts and states use this family; text and line styles retain meaning
without a colored status dot. Preserve the supplied logo's vector geometry and
gradients, with no tile, border or added caption. Earlier blue/beige treatments
are historical studies. Dark/Contrast variants remain to be designed.

Keep room identity and optional counts in the board menu, and selection on the
node. Remove floating page summaries, tutorial legends, pin hints and generic
authority footers. Units, age, missingness, source scope and exact Action review
remain visible where they support the current task. Detailed research and
implementation notes stay outside product screens.

A Thing node shows its name/type, connection status and a small number of
selected observations with units and age. Selection reveals its full details.
Process/experiment nodes have a distinct shape and label: a computation is not
a physical device. Edges name their relationship and direction, such as an
observation used by an experiment or a proposed control path. Screen proximity,
a dragged edge and an animated line establish no connection or Action authority.
Only relationships supplied by an admitted source are shown as established.

Canvas objects have two categories: authoritative subjects projected by the
server, and presentation objects such as metric pins. Removing a pin or hiding
a node changes the view. Disconnecting a Thing is a separate explicit operation.
Live updates change values without moving nodes or stealing focus.
Context menus reflect the selected source's capabilities. Unsupported
configuration, streaming or connection operations show a reason instead of
opening an empty task or implying that an adapter exists.

## Journey 1: establish and inspect a connected system

**Goal:** understand the current system and inspect one Thing without leaving it.

1. Open an existing owned workbench or an empty canvas. The empty state offers
   explicit sample-room startup and connection/import entry; browsing starts no
   room, discovery scan or experiment.
2. Start the sample room, or use a bounded connection dialog for an admitted
   source. Show connection progress, validation and refusal within that task.
3. See the Things and typed connections. Each source clearly says simulated,
   connected or unavailable. The first review fixture uses Thermostat, Energy
   meter and Actuator, with a separate smart-room computation node.
4. Select a Thing or open its context menu. Inspect, Metrics, Statistics,
   Configuration and Run history open the appropriate inspector tab. Available
   Property reads and Actions form a separate operations group.
5. Read a Property or observe an admitted stream explicitly. Values show units,
   last observation time and live/stale/offline state. Close the inspector and
   continue with the same selection, pan and zoom.

**Alternatives:** invalid Thing Description, missing credentials, refused scope,
transport loss and unavailable observations remain attached to the selected
subject. Missing measurements are gaps, not zero. Configuration edits retain a
draft and require explicit Apply. Opening an inspector performs no write.

**Design check:** the user can identify the system's state and inspect a Thing
without a page transition. Ellipsis and keyboard access expose the same actions
as right-click. A searchable list provides a non-spatial access path to Things.

## Journey 2: ask, inspect and compose a personal workbench

**Goal:** answer a measurement question and keep the useful result visible.

1. Open Metrics/Ask from a Thing or the floating palette. The composer shows its
   subject and scope before submission: Thing observations, the current Lab room,
   a selected run, or host metrics. Those sources are never silently combined.
   Host metrics require their explicitly activated operator capability; selecting
   a Thing or asking a question grants no host-wide access.
2. Ask a question, select a catalogue example, or use Build query. Free-form Ask
   uses the explicitly configured provider; catalogue selection and ordinary
   inspection remain usable without an LLM.
3. See the admitted query, result, range, units and concise explanation in the
   inspector. Sources and View query reveal the basis. Unsupported questions,
   missing series and unavailable providers give a useful correction path.
4. Choose Pin to workbench. A chart, statistic or table becomes a canvas object
   with a title, subject, time range, freshness and clear live/paused state.
5. Move and resize it beside the topology. Its menu offers rename, refresh,
   pause, inspect sources and remove. Save layout retains arrangement and query
   definitions. Freeze snapshot is a separate operation with a fixed time range.
6. Return later to the owned layout. Cached data remains visibly timestamped;
   a failed refresh does not present old values as live.

The structured handoff is proposed work. An AI answer may suggest only a closed
metric/query and supported visualization descriptor. The server admits the
source, scope, aggregation, range and limits before querying or pinning. No
model-generated HTML, SQL, JavaScript or arbitrary data URL enters a widget.
Pinning never schedules another model request. An explicit live-refresh choice
uses a bounded query/subscription policy and stops on pause, removal or teardown.
Retain the current ceiling of sixteen metric panels for the initial proposal.
The target includes named layouts owned by a principal within an admitted Lab
instance, with positions, sizes, viewport and validated query definitions.
Restoration rechecks source access and room identity; it never revives an expired
room or starts a run/provider request. Cached samples retain their own timestamp
and are separate from layout definitions. World-coordinate placement and durable
ownership need a versioned schema before implementation. Saving does not imply
cross-user sharing.

**Design check:** a user can go from a question to a useful pinned measurement,
inspect its basis, change its placement and recover it without navigating away
from the connected system. The no-provider Build query path reaches the same
kind of result and pin.

## Journey 3: run an experiment and explain its outcome

**Goal:** test something in the current system, understand its result and retain
the useful comparison.

1. Open Experiments from a selected subject or the palette. A compact drawer
   offers the admitted Thermal, Window anomaly and Smart room experiments.
2. Configure parameters in that context. Keep drafts through inspector changes;
   show errors beside fields. Run is an explicit submission.
3. Follow a step timeline and current state while the canvas remains visible.
   An activity badge lets the user close the drawer and return to that run.
4. Inspect the result: observations and numerical output, assertions, failures,
   cleanup and any inert Action proposal. Pin a supported result or comparison
   without turning the whole run into a new application page.
5. For an effectful proposal, open an exact-scope review: Thing, operation,
   input, freshness and expiry. Approve and Cancel are distinct actions. An
   expired outstanding decision requires explicit cancellation before a fresh
   smart-room run under the current host behavior.
6. Open Sources or Run details when explanation is needed; export a report
   explicitly. Back/close restores the selected run and previous canvas state.

The product does not need a permanent Evidence destination. Evidence is the
supporting record of what was observed, queried, configured and executed, with
its source/time/run identity. Present it as Sources, Run details, checks and
Export report. Detailed digests and raw records belong in expandable detail.
Human labels do not weaken the underlying WLB.06 record or WLB.11 approval rules.
Transport completion alone does not prove a physical effect.

**Recovery:** a lost connection marks values stale and command outcomes unknown
until refreshed authoritative state resolves them. Preserve pending-command
identity. Reconnection, opening a drawer, pinning and canvas gestures replay no
run, prompt, export, mutation or approval. Read-only canvas arrangement may
continue locally while server-backed operations wait for resynchronization.

## Journey 4: find documentation and return to work

Open documentation into a conventional document layout: 48-pixel branded header,
persistent global search, hierarchical left navigation, readable article column,
right table of contents when space allows, code/table overflow and previous/next
links. Search opens by keyboard or header control, covers the ecosystem corpus,
shows useful snippets and filters, and has clear empty/error states.
The header search is a compact 320 × 28 control. Navigation uses 28-pixel rows
within a roughly 216-pixel sidebar. Search results integrate into the article
column with hairline separators, concise snippets and a pale selected row.
Use flat surfaces without drop shadows, an outer modal card or nested result
cards. Product footers do not name DocShell, Pagefind or draft status.

Reading uses no workbench palette or room allocation. Return to workbench keeps
the owned board and selected subject; the implementation must define the safe
restoration mechanism rather than relying only on browser memory. Documentation
is also independently deep-linkable. Opening a contextual help article leaves
unsent configuration drafts intact.

Use the familiar Docusaurus information layout as a reference. Retain the
existing DocShell build and shared Pagefind index unless a demonstrated
requirement warrants changing them. Switching to a React documentation build
does not solve the Lab's interaction problem.

## Frontend recommendation and inspected source

**Use Svelte 5 and Svelte Flow for the interactive workbench, within the existing
Phoenix LiveView application.** LiveView owns routing, room/session identity,
authorization, canonical state and command outcomes. One composed, registered
workbench island owns the canvas, floating controls, local selection, menus and
inspectors inside its DOM boundary. Pointer movement, pan and zoom stay local.
Do not assemble the spatial surface from competing LiveView and Svelte owners.

This develops [Decision 0010](../decisions/0010-liveview-svelte-islands.md);
it adds no second browser router or Node runtime service. HEEx supplies the
semantic initial/failure view and searchable Thing list. Shared Svelte components
continue into Storybook. Svelte Flow is a proposed new dependency, not present
in the lockfile; select and qualify its exact version before implementation.

Inspection baseline: repository commit
`597598307b06407b0452491d269eda2487b828f9`, package `packages/wotex-lab`.
The host pins Svelte 5.57.1 and BeamLens 0.3.1. Its registered islands currently
cover tabs, data-grid and chart only; the primary Workbench is LiveView/HEEx.
The existing BeamLens skill offers bounded metric queries and current/baseline
run summaries. It has no structured prompt-to-widget protocol. Saved metric
arrangements already exist, but arbitrary spatial placement, live Thing node
subscriptions, connection authoring and the new composed island are unbuilt.

Per-Thing telemetry also needs explicit source work: the host-wide telemetry
ring deliberately excludes Thing IDs. A Thing context menu must not pretend
that host metrics are scoped to that device. The topology projection, source
capabilities and any new observation subscription require their owning contracts.

## Figma review and delivery order

Keep the existing [Lab file](https://www.figma.com/design/SudxgeebiNEu33PPIHO229)
and separate [brand file](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0).
Preserve prior draft identities and mark their visual direction superseded for
the current review. The maintainer-supplied
[logo source](https://github.com/wotex-project/wotex/blob/e7fdfa4a078f28908f2394120a5c2b8701c9013d/docs/assets/brand/wotex-logo-light.svg) now owns the mark;
the earlier W tile and typographic treatments remain historical studies.
Review small-size recognition and any future lockup separately.

1. Create a new canvas-journey proposal page with ten expanded states: four
   connect/inspect, four ask/compose and two configure/result. Use one stable
   illustrative system and shared compact controls. Give each journey its actor,
   goal, entry, outcome and recovery in an adjacent native Spec when supported.
2. Create a separate documentation journey page for search, results, article
   reading and return to workbench. Preserve the separate reading shell.
3. Connect the ordinary, close/back and cancellation paths in native Prototype
   and exercise them in Play. A right-click mockup alone does not prove a
   working context menu; exercise its ellipsis/keyboard entry as well.
4. Review a real-size composition together before promoting the proposal to
   implementation. Then add compact/medium, themes, unavailable/denied/stale,
   expiry/reconnect and keyboard variants to the selected direction. Retain
   the existing 599/600 and 839/840 task-container acceptance boundaries.
5. Promote the accepted changes into WLB.11, its catalogue, the completion
   contract and Decision 0010 as applicable. Build a vertical journey from the
   canvas through one Thing inspector and one query pin before broadening it.
   Continue with run/Action review and documentation integration, then the
   remaining component and recovery coverage. No application implementation is
   authorized merely by this proposed document.

Figma agent or Make may accelerate exploration with illustrative data. Native
editable Design layers remain the handoff. A runnable experiment, a connected
prototype and an executed host journey are separate deliverables and must be
reported separately. No purchase, publication or provider smoke is part of this
design pass.

## Authored proposal and bounded review

The 2026-10-21 edition adds two pages to the existing editable Design file:

| Page | Authored journey states |
| --- | --- |
| [Canvas journeys — proposal](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=61-2) | Start a sample room, connected Things, Thing context menu, Thing inspector; Ask, admitted metric result, pinned chart, pin/layout actions; experiment configuration and result/Action review |
| [Find answers — proposal](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=61-212) | Documentation search, results, article reading and return to the same workbench context |

These are fourteen expanded 1440 × 900 compositions with illustrative data,
editable text/vector layers and existing Button/Field instances. Compact
floating controls, typed topology edges, a contextual inspector and a metric
pin establish the proposed workspace. Shared-control studies are present but
have not been qualified as complete native component families. The initial
edition used a draft W tile; the subsequent visual revision uses the supplied
mark and compact grayscale direction above.

Manual review brought the context menu above the graph, removed unrelated
Actuator details and explanatory boilerplate from the Thermostat inspector,
shortened the Ask task, and corrected the metric's scope to the workbench
instance. The result and pin preserve the missing sample as a gap and show
units, range and observation time. This does not qualify real telemetry.

The compact grayscale revision retains all fourteen root frame identities.
Eleven canvas compositions now use the graph-paper pattern, represented in
Figma by three combined editable vector paths per background. The supplied
unboxed mark, two compact menu surfaces, 14/16-pixel Lucide icons, left-aligned
menu rows and shortened task labels replace the earlier treatment. D1–D3 use
the flat 48-pixel documentation header and integrated content; implementation
footers and shadowed search cards are removed. Existing restricted Button/Field
instance internals were retained. Representative A2/A3/B3 and D2 renders were
reviewed; the connect/inspect and Ask/result/pin paths were exercised again in
Play. Submenu, responsive and recovery qualification remains separate work.

Native Play exercised these fixed-state paths:

- Explicit sample-room start → connected Things → ellipsis menu → Inspect →
  Thing inspector → Close; selecting the Thing and returning with Back also
  preserved the connected-system composition.
- [Ask → admitted result → Pin](https://www.figma.com/proto/SudxgeebiNEu33PPIHO229?node-id=64-5510&starting-point-node-id=64%3A5510&scaling=scale-down-width&content-scaling=fixed)
  reached the pinned chart with the same host-instance query identity, range,
  units and missing-data gap.

The experiment and documentation states remain storyboards. General text input,
Build query, right-click/keyboard entry, menu dismissal, drag/resize, layout
persistence, run/approval/cancellation and documentation navigation have not
been qualified in the new prototype. No room, metric query, provider request,
run, Action or report export executed during Play. Adjacent journey notes are
ordinary Design content; native Specs were not updated in this edition because
the managed connector required reauthentication. Themes, responsive/recovery
coverage, full component bindings, native archives and independent restores
remain design acceptance work. Review this spatial direction before extending
those combinations or promoting implementation obligations.

## Research basis

Primary documentation inspected on 2026-10-21:

- [Miro toolbars](https://help.miro.com/hc/en-us/articles/360017730553-Toolbars):
  board controls, icon tools and viewport-oriented workspace conventions.
- [Svelte Flow built-in components](https://svelteflow.dev/learn/concepts/built-in-components),
  [custom nodes](https://svelteflow.dev/examples/nodes/custom-node) and
  [context menus](https://svelteflow.dev/examples/interaction/context-menu):
  a plausible implementation basis for the spatial surface and contextual UI.
- [Svelte Flow component API](https://svelteflow.dev/api-reference/svelte-flow):
  node/edge focus, context-menu events and local interaction configuration.
- [LiveView interoperability](https://phoenix-live-view.hexdocs.pm/1.2.12/js-interop.html)
  and [Svelte mount/unmount](https://svelte.dev/docs/svelte/imperative-component-api):
  separate DOM ownership and component teardown.
- [Docusaurus search](https://docusaurus.io/docs/search): familiar documentation
  search conventions; the selected Lab implementation remains Pagefind.
- [BeamLens 0.3.1](https://beamlens.hexdocs.pm/readme.html): optional configured
  runtime investigation; the Lab's own bounded skill determines actual access.
- [Figma agent](https://help.figma.com/hc/en-us/articles/37998629035799-Work-with-the-Figma-agent-in-design-files)
  and [Figma Make](https://www.figma.com/solutions/ai-design-generator/): native
  design exploration and executable studies have different output contracts.

Private reference-project inspection stays in ignored local research notes.
No reference project's source, data, private names or assets are imported.
