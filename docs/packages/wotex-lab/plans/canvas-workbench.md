# Canvas Workbench: journeys and design proposal

Plan version: 0.18.0. Status: iterative design review. Implementation: persistent
canvas and contextual tools; full workbench migration remains open. Owners: WLB.11 and
WLB.12. Package: `packages/wotex-lab`.

The Lab becomes a persistent spatial workbench for understanding a connected
system, investigating measurements and running experiments. A full-page canvas
holds Things, their typed connections and user-pinned results. Compact floating
tools and contextual inspectors support the current journey. Documentation has
its own conventional reading layout and global search.

This direction replaces the previous sidebar-led Figma drafts. WLB.11 version
0.16 accepts the grayscale geometry and bounded Thing-graph contract. Its first
source now opens a full-viewport Svelte Flow canvas at `/`. Experiments, runs,
metrics and selected-run evidence patch the same LiveView and open contextual
panels. Thing inspection/import, experiment drafts, explicit readings, node
positions and viewport survive those panel transitions. A bounded documentation
round trip now retains unsaved presentation and drafts. The compact built reader
is implemented on its explicit candidate dependency lane. Reference Thing
observations now retain separate Property receipts with Live, Stale, Paused and
unavailable states. General recovery and complete qualification remain open.
Room-scoped Ask → recorded chart → pin and manual Query → result → pin retain
source/query identity and missingness. Saved pin geometry and viewport restore
within the signed session; restored pins pause until Resume.
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
context menus start at 200 pixels. The board dropdown is 38 pixels high, hugs
its contents and leaves 4 pixels after the chevron. Touch and zoomed layouts need their own
composition. The source implements the board control and Select/Pan/Add Thing/
Metrics/Experiments/Fit rail. Opening these tools performs no read, history query
or run. Broader accessibility qualification remains open.

The 28-pixel field height applies to single-line controls. Questions and Thing
Description JSON use bounded multiline inputs that show their content without
repeating it in a separate preview paragraph.

Use one 4-pixel base radius for sections, nodes, menus, shells and controls.
The selected tool is a 28-pixel square with the same corners, inset 4 pixels
within the rail. Buttons take their width from their content. Put form groups
directly in the inspector body, with labels above fields, instead of nesting
another rounded card. Floating nodes, pins, menus and shells use a thin border
and shared subtle elevation: charcoal shadows at 0/2/8 pixels with 10% opacity
and 0/1/2 pixels with 4% opacity. Inner groups and integrated documentation stay
flat. This supersedes the earlier shadow-free canvas treatment.

Dark decorative borders use `#444B5A` rather than the bright mid-gray outline.
The selected/focus outline uses `#818A9D`. Light and contrast treatments retain
their separate roles; they do not inherit the dark-mode adjustment.

Keep floating inspectors 20 pixels inside the top, right and bottom canvas
edges, matching the board control's edge inset. Use one visible shell with
12-pixel content padding for inspectors and dialogs. Menus inset their rows
4 pixels, with 8-pixel row padding; labels therefore share the same 12-pixel
content inset. Rows must not paint over the continuous outer border. Numeric
readings and their units share a text baseline, including `°C target`.
Below 600 pixels the inspector starts at 76 pixels to clear the board control;
its left, right and bottom canvas insets remain 20 pixels.

The workbench background follows the supplied graph-paper reference: a fine
6.5-pixel mesh, secondary lines every 26 pixels and crosshairs every 104 pixels.
The softened [repeating SVG tile](https://github.com/wotex-project/wotex/blob/3de193854d03d4149376f8aae744bff443f37741/docs/assets/lab/workbench-grid.svg)
is 673 bytes, with no raster, font, script or external resource. Fine and
secondary strokes use 6.5% and 7.8% opacity; crosshairs use 65%. This reduces
contrast by 35% from the first graph-paper edition. Keep its origin consistent
with canvas pan/zoom during implementation; opaque data surfaces sit above it.

Icon artwork comes from Lucide revision
`20aef31db93fe4d9f398dbb15b120d99c48eef95`. The source SVGs and upstream
[license](https://github.com/wotex-project/wotex/blob/e7fdfa4a078f28908f2394120a5c2b8701c9013d/docs/assets/icons/lucide/LICENSE) are retained with their
[notice](https://github.com/wotex-project/wotex/blob/e7fdfa4a078f28908f2394120a5c2b8701c9013d/docs/assets/icons/lucide/NOTICE). This supplies design artwork;
the source shell and Thing graph reuse the selected SVGs with their notices.

Use Inter and the supplied logo's cool grays: `#181D27`, `#303644`, `#818A9D`,
`#9097A5` and `#D6DBE3`, with white and pale surface tints. Selected controls,
edges, charts and states use this family; text and line styles retain meaning
without a colored status dot. Preserve the supplied logo's vector geometry and
gradients, with no tile, border or added caption. Earlier blue/beige treatments
are historical studies. Light, Dark and Contrast now share semantic bindings
for the board control, surfaces, text, selected tools and borders. The grid
changes its foreground roles while retaining its spacing and opacity. Linked
[Dark workbench](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=269-6775)
and [Contrast experiment](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=269-6992)
compositions cover topology, a pin and contextual inspectors. Representative
theme journeys passed native Play; failure-state and responsive qualification
remains.

The separate [identity Spec](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=20-219)
documents the selected mark and derived dark/monochrome treatments. The
[export handoff](https://github.com/wotex-project/wotex/blob/main/docs/assets/brand/exports/README.md) includes native-source
SVG, favicon, application and social artwork with dimensions and hashes.
These design assets do not change the current browser implementation.

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

The sample Thermostat declares a read-only, observable `temperature` Property.
Its operations menu offers Read Property and explicit Observe/Pause. The sample Actuator owns
`setTarget`; that Action belongs to its admitted proposal and explicit review
journey. Registering a Thing Description creates a Directory entry; it does not
establish a transport connection. These distinctions also govern the import,
unavailable-metrics and configuration states.

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

### Configure a typed connection

Open Connections from the compact rail, select a connection, or drag between
declared handles. The same editor selects a current admitted Thing and
compatible Property or proposal target. A gesture opens a draft and adds no
edge. Sources discloses the exact Thing, affordance, schema unit and Forms.
Read and Observe remain separate explicit operations on the selected source.

Apply and Remove compare the room's connection revision. A stale draft remains
editable until explicit reload or correction; a pending Action decision blocks
configuration changes. Back and Close preserve an uncommitted draft; Cancel
discards it. Applied wiring survives reload in the owning room, and the next
explicit Run records and uses its selected endpoints. Missing required input
fails before any Property read. The meter-off path preserves its existing
missing-power fill and mask. Configuration starts no transport, observation,
experiment or Action. Inert Directory entries remain unavailable as sources.

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

Across an unavailable chart interval, a light gray dotted bridge joins the
known endpoints and is identified as “Dotted · no samples”. It signals absent
observations, not measured interpolation. Do not add points or turn missing
samples into zero. Sources retains the exact unavailable interval; measured
segments remain solid charcoal.

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
4. Inspect the outcome and compact charts first. Data, Analysis, Run details,
   Sources and Ask open separate contextual views of the same owned Run.
   Display charts use elapsed seconds; Data retains exact timestamps, dtype,
   shape, values, masks and quality. Assertions, parameters and cleanup belong
   in Run details. Pin a supported result or comparison as an immutable capture
   with its outcome, chart, exact record and query. Rename, arrange, inspect its
   captured Sources or reopen the source Run from the canvas. Pinning and
   restoration execute no experiment or query; Run pins have no refresh loop.
5. For an effectful proposal, open an exact-scope review: Thing, operation,
   input, freshness and expiry. Approve and Cancel are distinct actions. An
   expired outstanding decision requires explicit cancellation before a fresh
   smart-room run under the current host behavior.
6. Open Sources or Run details when explanation is needed; export a report
   explicitly. The Run export contains only the selected record, proposal,
   decision and dispatch, with an explicit Run scope. Back/close restores the
   selected result and previous canvas state.

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
continue into Storybook. Svelte Flow is now pinned in the host lockfile and
owns the implemented canvas island.

Inspection baseline: repository commit
`597598307b06407b0452491d269eda2487b828f9`, package `packages/wotex-lab`.
At that baseline, the host pinned Svelte 5.57.1 and BeamLens 0.3.1. Its registered
islands covered tabs, data-grid and chart; the primary Workbench was
LiveView/HEEx. The current source adds the composed spatial canvas, saved node
positions and metric pins, bounded metric composition, explicit reference
Property observations and typed reference connection authoring. Source changes
and their executed checks are recorded separately from archive adoption.

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
   goal, entry, outcome and recovery in a native Figma Spec. Do not render
   descriptions or implementation notes as text boards in the product canvas.
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

The 2026-10-21 review uses these pages in the existing editable Design file:

| Page | Authored journey states |
| --- | --- |
| [Canvas journeys — proposal](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=61-2) | Start a sample room, connected Things, Thing context menu, Thing inspector; Ask, admitted metric result, pinned chart, pin/layout actions; experiment configuration and result/Action review |
| [Find answers — proposal](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=61-212) | Guides, API, packages, search/scopes, empty/error/missing states, responsive representatives and theme specimens |
| [Compact system](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=96-52) | Seventeen core control/container families, semantic colour modes, eight text styles and linked instance reviews |

The initial edition contains fourteen expanded 1440 × 900 compositions with
illustrative data, editable text/vector layers and existing Button/Field
instances. Compact
floating controls, typed topology edges, a contextual inspector and a metric
pin establish the proposed workspace. The separate compact library now supplies
core control families; the subsequent container and journey edition is described
below. The initial
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

The compact library contains fifty variants across Button, Icon button, Field,
Tab item, Menu item, Status, Tool rail, Board control and Menu surface. It uses
semantic aliases in Light, Dark and Contrast, six named Inter styles and exact
Lucide vector masters. The supplied logo remains unboxed vector artwork.
Linked [control](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=97-1650)
and [three-mode](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=97-2096)
reviews were inspected. These native controls do not establish parity with the
host's current CSS or complete responsive accessibility coverage.

The next edition adds Thing node, Process node, Metric pin, Inspector shell,
Dialog shell and Field group families. Together with the core controls, these
provide fifteen families and sixty-five variants. A linked
[container review](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=106-1424)
was inspected. State-specific properties retain stale timestamps, paused or
missing metric data and invalid-field errors; a shared default must not relabel
those variants as current. The gapped chart remains editable vector artwork.

Eight existing A/B roots now use the compact components, retaining their root
identities and eleven existing prototype reactions. Five legacy control
instances retained their identities through component swaps. Five older click
targets remain aligned, nearly transparent prototype overlays; they preserve
historical links and are not a proposed runtime DOM pattern.

Sixteen additional expanded storyboards complete the first connection and
metrics state inventory:

| States | Additional task coverage |
| --- | --- |
| A5–A8 | Board menu, Add submenu, [Thing Description import](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=111-3866) and retained invalid input |
| A9–A12 | Searchable Thing list, stale observation, unavailable per-Thing measurements and read-only Thermostat configuration |
| B5–B8 | [Build query](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=111-5011), query/source detail, unavailable Ask provider and absent measurements |
| B9–B12 | Save layout, saved entry, [restored cached board](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=111-6203) and paused pin; B4 retains pin actions |

The proposal now has twenty-six canvas snapshots and twenty-nine documentation
fixtures: twenty-six content/layout compositions, two theme specimens and a
returned-board fixture. The two experiment snapshots use the same compact topology
and inspectors as the connection and metrics journeys. Source comparison for
this edition used repository commit `8445530535732324d28f935abac530e97c3aab2f`
and package path `packages/wotex-lab`; later source changes require comparison.

There are seventy-seven current standalone targets, including fifteen
full-viewport documentation overlays. Before the documentation addition,
fifty-five of sixty-two menu, inspector and dialog targets were structurally
reachable from A1's explicit sample-room start. Seven alternatives remain separate review
fixtures: invalid Thing Description, unavailable Ask, no measurements, cached
refresh, unavailable experiment, expired decision and denied Action. Five
replaced helpers are hidden archives. Reachability does not establish that
every control, state transition or backend contract was exercised.

The latest native edition adds:

- Distinct Thermostat, Energy meter and Actuator menus, inspectors, Property
  results, history limits, configuration limits and Sources. Actual Thing IDs,
  Forms and capabilities replace the earlier Thermostat placeholder identity.
- Board-preserving pin, pause, resume, remove, rename and Sources actions.
  Hidden prototype variables retain pin title/visibility, paused state and layout
  status. Saving changes the illustrative layout status; durable storage,
  arbitrary text editing and arrangement are not implemented by this prototype.
- Separate [Thermal](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=199-5139),
  [Window anomaly](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=199-5253)
  and [Smart room](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=199-5026)
  tasks, with result, Sources, Run details and report compositions. Count 513
  shows the anomaly error while retaining its other five fields and disabling
  Run. Its result now shows the executed sample's score, observed temperature
  window and persistence prediction. Broader numerical/state validation remains
  required.
- Exact Action review, unknown command outcome, accepted transport and explicit
  target Property read states. Hidden stage variables resume the current
  proposal or command after closing the drawer. The proposal can be cancelled
  explicitly. An accepted command has a separate New run entry. This models
  presentation behavior, not policy decisions, command execution or effect.
- Compact action rows, growing multiline import text and shared field groups
  that hug their visible contents. Hidden validation text no longer reserves
  blank space. Smart-room configuration has no inner form card. Buttons and
  single-line fields retain the shared 28-pixel height and 4-pixel corners.
- Documentation content and shell families add nineteen variants. Fifteen
  content states cover guides, API overview, `read_property/3`,
  `observation_child_spec/4`, the twenty-package index, package detail, search,
  scoped results, empty results, search failure and missing documents. The
  search shell uses the full content column, without a modal or nested card.
  Elixir examples follow the public runtime source; JetBrains Mono 12/18 joins
  seven Inter text roles. Menu, copy and external-link icons use the same pinned
  Lucide revision as the existing artwork.
- Expanded, 839-pixel and 599-pixel representatives plus 375/600/840-pixel guide
  fixtures share the same documentation components. Narrow navigation uses a
  drawer, and on-page contents uses an inline disclosure. Light, Dark and
  Contrast guide specimens were visually reviewed with native text, vectors
  and linked instances; no complete-screen raster is present. The original
  logo is unchanged; derived dark-surface and monochrome treatments are
  proposals for review.
- Twenty existing storyboards now embed the current compact task panels,
  menus and dialogs instead of older copies. Root frame identities remain;
  replaced bodies and obsolete hotspots are hidden. Embedded task actions
  enter the canonical A2 overlay flow. The valid import preview now shows
  parseable Thing Description JSON with the actual simulated Property Form.

Native Play exercised these fixed-state paths:

- Explicit start → connected Things; board Search → Find → Thermostat → Close.
  Energy meter opened its own right-aligned inspector. Context menus retained
  their anchors, and closing an inspector retained the board.
- Metrics → Ask → result → Sources / Build query → result → Pin on the same A2
  canvas. Pin Pause → paused menu → Resume → Remove retained the Things,
  connections, query identity and last sample time without navigating to a
  copied board. Ask was exercised again after removing its duplicate heading.
- Smart room Run → result → Action review → unknown command outcome → Check
  status → accepted. Closing and reopening Experiments resumed the pending
  proposal, unknown command and accepted status without another Run or approval.
  These are fixed prototype transitions, not observations from a device.
- New run → anomaly configuration → invalid count 513 → Reset count → result
  exercised validation and recovery while retaining the other five fields.
- The refreshed C1 storyboard's Run entered the canonical A2 result overlay
  and updated the process label to Pending review. Use A1 as the ordinary
  prototype start; direct storyboard entries use fixed presentation defaults.
- Board menu → Documentation → search → Enter results → Down/Enter opened
  `read_property/3`. Packages → `wotex_nx` showed its own summary and hid
  runtime-specific links. Ask → result → Pin → Documentation → Return retained
  the metric pin on the actual A2 board. Documentation now opens as a
  full-viewport overlay; navigation swaps within it and Return closes it.
  The separate page-06 returned-board frame remains a review fixture.
- The 375-pixel guide's navigation drawer opened and Escape closed it; the
  on-page contents disclosure expanded in place. Complete narrow detail flows
  and keyboard/focus equivalence remain separate checks.
- Dark mode persisted through Thing menu → inspector → Property read;
  Ask → result → Sources → Pin; documentation search → keyboard selection →
  API → Return; and Smart room Run → review → unknown command outcome →
  accepted. Switching to Contrast retained the pin and accepted command
  identity without another Run. After reload, corrected Dark hints and straight
  search-row dividers were visually checked.
- Presentation entries now read Connect and inspect, Ask and pin, Run and
  review, and Find answers. Run and review starts at C1 configuration. The
  reader distinguishes board entry from direct entry: board Return closes to
  its origin, while direct-entry Return navigates to the A2 review fixture.
  Native Play returned to the exact C1 URL with its Dark configuration panel
  still open, and separately exercised direct-entry Return. This is prototype
  context, not application session restoration.

A structural theme audit covered 105 current journey/review roots and 2,308
visible text nodes, finding no primitive-bound or unbound solid text fills.
This checks color bindings, not interaction completeness or accessibility
certification. Search-result dividers are straight; controls and floating
shells retain the shared 4-pixel radius.

The final compact workbench/result, anomaly form, Ask, import and query builder
renders were visually reviewed. The native
[journey Spec](https://www.figma.com/design/SudxgeebiNEu33PPIHO229?node-id=119-4210)
is now the Start-page entry. Managed access was restored, its content was read,
updated with surgical edits and read back. Superseded page families are marked
Archive, and the old Start, journey and layout prose boards are hidden.

Separately from Play, the pure `Wotex.Lab.Examples.WindowAnomaly.run/1` example
was executed with seed 1, count 32, window count 8, threshold 1.5, fill 18.0 and
`Nx.BinaryBackend`. The encoded window had shape `{8}`, dtype `f32`, eight
observed masks and eight good-quality codes. The scalar score was
`0.03721809387207031`, below threshold; the persistence prediction was
`18.14862823486328` Cel at 32 seconds. These source-derived values now populate
the fixed anomaly preview. This validates that sample, not general numerical
acceptance, backend equivalence or runtime execution from the Figma control.

General text input, right-click/keyboard equivalence, drag/resize, durable
layout restoration, all seven alternatives, expiry/denial semantics, real
reconnect, full result visualizations and report downloads remain unqualified.
No room, metric query, provider request, experiment, Action or report export
executed during Play. Documentation still uses a fixed search fixture;
general typing, live indexing, clipboard copy and contents scrolling are not
exercised browser features. Empty/error/missing states are authored review
fixtures. Complete responsive/detail flows, failure-state theme review,
remaining component bindings, native archive recovery and final brand review
remain acceptance work. Application UI implementation has not started; source
contracts remain authoritative until the proposal is reviewed and promoted.

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
