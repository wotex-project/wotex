# Frontend source standard

The Workbench frontend uses functional TypeScript and Svelte 5 composition.
This standard covers `hosts/workbench/assets/`, its Storybook configuration,
frontend build/check tools and the standalone Storybook host's lazy loader.
The generated control SDK has a separate public constructor API under WLB.08;
this UI refactor does not change that API or its generator.

## Functions and state

Use `const` arrow functions and arrow operation properties. Do not declare
functions, use function expressions, object method shorthand or application
classes. Object getters and setters remain available. Script callbacks use
arrows; named functions must use `const`, not `let`.

Stateful objects come from a `create…` factory with private closure locals and
a plain returned object. Export the shape as
`export type Session = ReturnType<typeof createSession>`. In `.svelte.ts`
modules, keep `$state` and `$derived` inside the factory and expose current
values through getters. Add setters only for values consumers already assign
or bind. Keep operation callbacks and effects in the instance that owns them.
Pass framework receivers explicitly; `createLiveViewHook` adapts LiveView's
receiver without application `this` or shared instance state.

A coded failure is an interface extending `Error`, a branded factory using
`Object.assign(new Error(message), …)` and a type guard that checks the Error
and its brand. Do not subclass `Error`. A helper returning `never` needs an
explicit function type on its const, for example
`const fail: (reason: string) => never = (reason) => { throw new Error(reason) }`.
Assertion helpers likewise retain their explicit callable type.

Define functions before code evaluates them. Avoid nested ternaries and
parameter reassignment. A declaration's position must be safe through local
calls, aliases, object arrow operations and synchronous iterable callbacks.
The ordering check follows those calls transitively, respects local/parameter
shadowing and terminates recursion. Function bodies are otherwise deferred.
Known deferred ports are Svelte effects, `$derived.by`, mount/destroy hooks,
timers/microtasks/animation frames, event listeners, LiveView event subscriptions,
promise continuations and test/lifecycle callbacks. Passing a function reference
still evaluates that reference immediately. Runtime import cycles must be
reviewed as part of an AST inventory; the ordering gate does not simulate a
JavaScript module loader or prove arbitrary dynamic dispatch safe.

## Components and controls

A non-story `.svelte` file has at most 300 lines. Split by responsibility;
keep the surface's path, props, behavior, DOM ids, test ids, ARIA attributes,
classes and localized text. Private children live in a sibling folder with
the surface's basename; children shared in an area stay flat in that area.
Move pure logic to `.ts` modules and rune state to `.svelte.ts` factories.
Children receive values and `on<Verb>` callbacks and do not fetch. Use
`$bindable` only to preserve an existing two-way seam. Move scoped styles
with their markup.

Templates pass named handlers by reference. Inline arrows/functions are
forbidden in event attributes, `on…` callback props and legacy `on:` directives.
A single trivial item action may use a named curried handler such as
`onclick={select(item.id)}`. A repeated row with several handlers owns a child
component with local handlers.

Raw `button`, `input`, `select` and `textarea` belong in
`assets/primitives/`. Domain components compose those controls. Public and
shared components have colocated stories; private children are covered by
their owning surface's stories. Native attribute and attachment forwarding
preserves existing DOM behavior. Labelled controls reuse the native control
primitive. Behavior regressions belong in the Elixir browser suite; pure
frontend mechanisms use Node unit tests. Story examples use Mix-owned seeds.
Internal application imports use `$lib`/`$seeds` and actual `.ts` extensions.

## Readability and formatting

Keep two-space indentation, 100 columns, double quotes, semicolons only where
needed, trailing commas, braces and existing Svelte template formatting.
Do not enable one-attribute-per-line formatting. Add blank lines between
functions, type declarations, imports and following code, test/lifecycle groups,
and multiline object methods/accessors/arrow properties. Compact members stay
compact. The syntax-aware spacing pass preserves comments and string contents.

`pnpm run format` runs Biome formatting and the spacing pass. It does not run
the style gate or perform semantic refactors. `pnpm run lint` runs Biome and
the read-only AST gate, including a spacing check. Run one area from the
repository root with:

```sh
pnpm --dir packages/wotex-lab/hosts/workbench run lint:style assets/components/canvas
```

## Enforcement and exemptions

[Biome configuration](../../../packages/wotex-lab/hosts/workbench/biome.jsonc)
pins 2.6.2; the standalone Storybook host extends it and runs Biome in its
own host directory through `tools/lint/biome-host.ts`. Plugin resolution stays
relative to the declaring configuration. Its installed schema defines `style/noParameterAssign`,
`style/noNestedTernary`, `nursery/useConsistentFunctionStyle` with expression
style, `nursery/noThisOutsideOfClass` and `complexity/useArrowFunction`.
The existing rule groups, complexity limit and formatter settings remain.
The [class](../../../packages/wotex-lab/hosts/workbench/tools/lint/biome/no-classes.grit),
[function expression](../../../packages/wotex-lab/hosts/workbench/tools/lint/biome/no-function-expressions.grit) and
[object method](../../../packages/wotex-lab/hosts/workbench/tools/lint/biome/no-object-methods.grit)
plugins reject those constructs. Their
`**/`-prefixed includes cover TS, JS, MJS and CJS. Regression tests invoke the
installed binary on temporary files and require the intended diagnostic.

[`frontend-style.ts`](../../../packages/wotex-lab/hosts/workbench/tools/lint/frontend-style.ts)
parses Svelte with `modern: true` and scripts with TypeScript, reporting
`path:line:column rule: message`. The
[ordering](../../../packages/wotex-lab/hosts/workbench/tools/lint/ordering.ts),
[spacing](../../../packages/wotex-lab/hosts/workbench/tools/lint/spacing.ts) and
[component ownership](../../../packages/wotex-lab/hosts/workbench/tools/lint/layout.ts)
checks share that source gate. The runner accepts file/directory arguments.
Malformed source fails; strings containing prohibited syntax are not findings.

Only platform constructors can justify a class exemption:

- Production Custom Elements must extend `HTMLElement`, be listed by exact
  path in the AST options and have matching plugin negations. None are
  registered in this frontend.
- Named `ResizeObserver`, `IntersectionObserver` or `MutationObserver` doubles
  may be classes only in `*.test.ts`. The class plugin excludes test files;
  the AST gate closes that broad plugin exclusion by rejecting other test
  classes. Method syntax inside these platform classes remains valid.

No raw-control embed exemptions are currently registered. An intentionally
self-contained embed needs an exact-file registration and a standard update;
placing domain code in an `embeds` folder does not exempt it.

The Workbench package gate calls `mix assets.check`, which runs
`pnpm run check`: lint, full dependency audit, type checking, unit/gate tests,
production build and asset budgets. `test:layout` includes `tools/lint/*.test.ts`;
Biome includes those modules and loads all three plugin files. The current Lab
CI package lane already selects every change under `packages/wotex-lab/`, runs
this host gate and the Storybook build, then runs Elixir browser journeys.
Thus edits to gate modules, plugin files and their tests are CI inputs without
another path-filter list. A failed rule or regression returns a failing status.
The complete browser commands are in `hosts/workbench/README.md`.
