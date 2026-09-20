# Decision 0010: Use Svelte islands inside the LiveView Workbench

Decision date: 2026-09-20. Status: accepted. Owners: WLB.08, WLB.11 and
WLB.12. This decision extends the LiveView host selected in
[Decision 0003](0003-native-workbench-and-observability.md) and supersedes the
HEEx-only renderer restriction in
[Decision 0007](0007-native-svg-chart-rendering.md). It does not weaken that
decision's closed chart descriptor, bounds, missing-value semantics, table
alternative or server-owned evidence.

## Context

The Workbench needs server-authorized real-time behavior and a maintained
frontend system. LiveView provides session ownership, process lifecycle,
server-side validation, change tracking and reconnect handling. Svelte provides
local interaction state, component composition, animation, high-frequency
pointer behavior, browser rendering and a static Storybook toolchain.

Choosing only HEEx would retain the server model but leave the component
catalogue, client-rich controls and design-system tooling weaker than the
accepted product surface. Replacing LiveView with a Svelte single-page
application would duplicate routing, synchronization, authorization and
command protocols. Letting both renderers update the same DOM would make focus,
cleanup and reconnect behavior indeterminate.

Phoenix LiveView supports external DOM owners through hooks and
`phx-update="ignore"`. Svelte 5 provides explicit mount and unmount APIs.
LiveSvelte 0.18 demonstrates full props, JSON Patch updates, streams, forms,
uploads and navigation over a LiveView hook. Phoenix Assets already owns Vite,
Storybook supervision and Svelte packages, while the current LiveSvelte release
requires `phoenix_vite` and provides a separate Node SSR path. Installing both
asset owners would duplicate process, manifest and deployment responsibilities.

## Decision

The Workbench remains a Phoenix LiveView application and may mount registered
Svelte 5 components through the PHA.02 island adapter in Phoenix Assets. Svelte
is not a second router or application root.

LiveView owns:

- routing, session and room identity;
- authorization, policy and command admission;
- experiment, query, evidence and Action lifecycle;
- canonical state and server-side validation;
- revision assignment, reconnect resynchronization and command deduplication;
- finite public projections sent to the browser.

Svelte owns:

- descendant DOM inside one registered island mount root;
- local hover, focus, selection, disclosure and unsubmitted control state;
- admitted charts, data grids, arrangement controls and browser-intensive
  presentation;
- animation and transitions subject to reduced-motion policy.

Phoenix Assets owns the island hook, closed component registry, transport
envelopes, design-system tokens and CSS, generic Svelte/HEEx components, Vite
graph and static Storybook. Wotex Lab supplies semantic theme overrides and
projects domain data into bounded public props. Wotex policy and domain names do
not move into Phoenix Assets.

The host does not depend on LiveSvelte or `phoenix_vite`. PHA.02 implements the
same established hook lifecycle through the existing Phoenix Assets Vite and
manifest boundary. The reference release starts no Node process. Each island
has useful HEEx fallback content and mounts on the client.

Each island has a LiveView-owned outer boundary with a patchable HEEx fallback
and an ignored inner mount root. Svelte owns only the mount root's descendants.
The adapter's preserved readiness attribute performs the accessibility handoff;
the hook never edits the fallback DOM.

The existing server-rendered SVG chart remains the semantic and no-JavaScript
fallback. A registered Phoenix Assets reporting island may enhance the same
closed descriptor with local inspection, hover, selection and admitted
pan/zoom. It cannot accept Vega specifications, expressions, remote data URLs,
arbitrary transforms or caller JavaScript. A client selection that changes
data, evidence or authorization returns to LiveView.

## State and failure rules

Every snapshot and patch carries component, instance, generation and revision
identity. A stale, skipped, malformed or wrong-instance patch is not applied;
the island requests a full snapshot. Reconnect never replays an unacknowledged
Action, mutation, approval, export or prompt submission. Server-backed controls
show the disconnected state until resynchronization completes.

Props are browser-visible and come from allowlisted projection functions.
Sockets, assigns, PIDs, functions, credentials, policy internals and arbitrary
struct fields are forbidden. Every client event is untrusted input and passes
the same session, scope, freshness, bounds and authorization checks as an HEEx
event.

An island failure leaves its fallback and error state visible and does not
disconnect the page. Hook destruction unmounts Svelte and releases listeners,
timers, observers and subscriptions. LiveView and Svelte never mutate the same
subtree.

## Design-system and catalogue consequences

The authored token source follows Design Tokens Community Group 2025.10.
Phoenix Assets generates the CSS, Elixir and TypeScript representations. Wotex
overrides semantic theme roles instead of forking component styles.

The public static Storybook renders the same Svelte module imports used by the
Workbench island registry. Deterministic mock transports demonstrate component
states but do not claim server authorization or persistence. A separate Phoenix
Storybook reference host exercises the HEEx wrapper and real LiveView transport.
The public static catalogue and optional live catalogue disclose those
different capabilities.

## Consequences

- Rich components can use Svelte without replacing LiveView or copying its
  state machine into the browser.
- Storybook documents production components rather than a parallel visual
  implementation.
- The Workbench adds an npm/Svelte asset build, but the base `wotex_lab` library
  remains usable without Phoenix, Node, Vite, Svelte or a browser.
- Static and JavaScript-disabled surfaces retain admitted HEEx fallbacks. They
  do not imitate live-only commands.
- Browser, reconnect, lifecycle-leak, accessibility, visual and asset-budget
  evidence becomes part of WLB.11 acceptance.

## Primary sources inspected

- [Phoenix LiveView 1.2.12 JavaScript interoperability](https://hexdocs.pm/phoenix_live_view/1.2.12/js-interop.html): hook lifecycle, `phx-update="ignore"`, client/server events and reconnect callbacks.
- [Phoenix LiveView 1.2.12 syncing changes](https://hexdocs.pm/phoenix_live_view/1.2.12/syncing-changes.html): patch-aware client operations and optimistic UI boundary.
- [Svelte 5 imperative component API](https://svelte.dev/docs/svelte/imperative-component-api): explicit `mount`, `hydrate` and `unmount` lifecycle.
- [LiveSvelte 0.18 introduction](https://live-svelte.hexdocs.pm/introduction.html): LiveView-hook-Svelte layering and reactive prop transport.
- [LiveSvelte 0.18 usage](https://hexdocs.pm/live_svelte/basic_usage.html): ignored DOM ownership and Svelte 5 component mounting.
- [Storybook Svelte/Vite integration](https://storybook.js.org/docs/get-started/frameworks/svelte-vite): Svelte 5/Vite component catalogue and static output without a SvelteKit application.
- [Storybook accessibility testing](https://storybook.js.org/docs/writing-tests/accessibility-testing): browser component checks and the limits of automated WCAG detection.
- [Phoenix Storybook](https://github.com/phenixdigital/phoenix_storybook): function/LiveComponent stories, variations, playground and router-mounted runtime.
- [Phoenix Storybook CVE-2026-8467](https://github.com/advisories/GHSA-55hg-8qxv-qj4p): public-playground exposure and the 1.1.0 security fix.
- [Design Tokens Format Module 2025.10](https://www.w3.org/community/reports/design-tokens/CG-FINAL-format-20251028/): stable cross-tool token exchange format; Community Group report, not a W3C Recommendation.
- [WAI-ARIA Authoring Practices patterns](https://www.w3.org/WAI/ARIA/apg/patterns/): component semantics and keyboard interaction references.

Inspection date: 2026-09-20. These sources establish design and API choices.
WLB.08 still requires exact dependency locks, licenses, artifact digests and
positive/negative integration evidence before an availability claim.
