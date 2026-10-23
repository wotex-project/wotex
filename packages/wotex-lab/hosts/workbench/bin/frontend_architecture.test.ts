import assert from "node:assert/strict"
import test from "node:test"
import { formatFunctionSpacing, inspectFrontendSource } from "./frontend_architecture.ts"

test("arrow factories and delegated Svelte callbacks pass the architecture contract", () => {
  const source =
    '<script lang="ts">\nimport { choose } from "$lib/choice.ts"\n\nconst select = () => choose()\n</script>\n<button onclick={select}>Select</button>'
  assert.deepEqual(inspectFrontendSource("assets/components/choice/choice.svelte", source), [])
})

test("classes, function expressions/declarations and object methods are refused as syntax", () => {
  for (const source of [
    "class State {}",
    "const state = class {}",
    "function choose() {}",
    "const choose = function () {}",
    "const state = { choose() {} }",
  ]) {
    assert.ok(inspectFrontendSource("assets/example.ts", source).length > 0, source)
  }
  assert.deepEqual(
    inspectFrontendSource("assets/example.ts", 'const message = "class State {}"'),
    [],
  )
})

test("internal imports use aliases and actual TypeScript extensions", () => {
  const errors = inspectFrontendSource("assets/example.ts", 'import { choice } from "./choice.js"')
  assert.ok(errors.some((error) => error.message.includes("alias")))
  assert.ok(errors.some((error) => error.message.includes(".ts")))
  for (const source of [
    'const load = () => import("$lib/choice.js")',
    'type Choice = typeof import("$lib/choice.js")',
  ]) {
    assert.ok(
      inspectFrontendSource("assets/example.ts", source).some((error) =>
        error.message.includes(".ts"),
      ),
    )
  }
  assert.deepEqual(
    inspectFrontendSource("assets/example.ts", 'import { choice } from "$lib/choice.ts"'),
    [],
  )
})

test("markup accepts delegated calls and rejects mutation or branching handlers", () => {
  for (const callback of [
    "() => { choose(); close() }",
    "() => selected = true",
    "() => selected ? choose() : close()",
    "function () { choose() }",
  ]) {
    const source = `<button onclick={${callback}}>Choose</button>`
    assert.ok(
      inspectFrontendSource("assets/example.svelte", source).some((error) =>
        error.message.includes("Delegate"),
      ),
    )
  }
  assert.deepEqual(
    inspectFrontendSource(
      "assets/example.svelte",
      "<button onclick={() => choose(id)}>Choose</button>",
    ),
    [],
  )
})

test("function spacing is deterministic in modules and Svelte scripts", () => {
  const source = "const first = () => 1\nconst second = () => 2\n"
  const formatted = formatFunctionSpacing("assets/example.ts", source)
  assert.equal(formatted, "const first = () => 1\n\nconst second = () => 2\n")
  assert.equal(formatFunctionSpacing("assets/example.ts", formatted), formatted)
  const component = `<script lang="ts">\n${source}</script>\n<p>Readable</p>`
  assert.equal(
    formatFunctionSpacing("assets/example.svelte", component),
    `<script lang="ts">\n${formatted}</script>\n<p>Readable</p>`,
  )
})
