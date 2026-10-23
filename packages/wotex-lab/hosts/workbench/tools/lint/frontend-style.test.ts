import assert from "node:assert/strict"
import test from "node:test"
import { inspectFrontendSource } from "./frontend-style.ts"

const rules = (source: string, file = "assets/example.ts") =>
  inspectFrontendSource(file, source).map((issue) => issue.rule)

test("scripts reject declarations, expressions, object methods and non-const arrows", () => {
  for (const source of [
    "function run() {}",
    "const run = function () {}",
    "const api = { run() {} }",
  ]) {
    assert.ok(rules(source).includes("arrow-functions"), source)
  }
  assert.ok(rules("let run = () => 1").includes("const-functions"))
  assert.deepEqual(rules('const message = "function run() {}"'), [])
  assert.deepEqual(rules("const run = () => 1"), [])
  assert.deepEqual(
    rules(
      "const createState = () => { let value = 1; return { get value() { return value }, set value(next) { value = next }, reset: () => { value = 0 } } }",
    ),
    [],
  )
})

test("only registered Custom Elements and named platform constructor test doubles permit classes", () => {
  for (const source of [
    "class State {}",
    "const State = class {}",
    "export default class State {}",
  ]) {
    assert.ok(rules(source).includes("no-classes"))
  }
  assert.ok(rules("class State {}", "assets/state.test.ts").includes("no-classes"))
  assert.deepEqual(rules("class ResizeObserver {}", "assets/observer.test.ts"), [])
  assert.ok(rules("class ResizeObserver {}", "assets/observer.ts").includes("no-classes"))
  const file = "assets/embeds/status-element.ts"
  const source = "class Status extends HTMLElement {}"
  assert.ok(rules(source, file).includes("no-classes"))
  assert.deepEqual(inspectFrontendSource(file, source, { customElements: [file] }), [])
  assert.ok(inspectFrontendSource(file, "class Status {}", { customElements: [file] }).length > 0)
})

test("Svelte scripts and module scripts report exact paths, lines, columns and rules", () => {
  const source =
    '<script module lang="ts">\nclass State {}\n</script>\n<script lang="ts">\nfunction run() {}\n</script>\n<p>View</p>'
  const issues = inspectFrontendSource("assets/view.svelte", source)
  assert.ok(
    issues.some((issue) => issue.line === 2 && issue.column === 1 && issue.rule === "no-classes"),
  )
  assert.ok(issues.some((issue) => issue.line === 5 && issue.rule === "arrow-functions"))
  assert.ok(issues.every((issue) => issue.path === "assets/view.svelte"))
})

test("events, callback props, uppercase names and legacy directives refuse inline functions", () => {
  for (const markup of [
    "<button onclick={() => choose(id)}>Choose</button>",
    "<Panel onSelect={() => choose(id)} />",
    "<button on:click={() => choose(id)}>Choose</button>",
    "<button onclick={function () { choose(id) }}>Choose</button>",
  ]) {
    assert.ok(
      rules(markup, "assets/primitives/demo/demo.svelte").includes("named-handlers"),
      markup,
    )
  }
  for (const handler of ["choose", "select(item.id)"]) {
    assert.deepEqual(
      rules(`<button onclick={${handler}}>Choose</button>`, "assets/primitives/demo/demo.svelte"),
      [],
    )
  }
})

test("all four raw controls are restricted to primitives and file size is bounded", () => {
  for (const control of ["button", "input", "select", "textarea"]) {
    const markup = control === "input" ? "<input>" : `<${control}></${control}>`
    assert.ok(rules(markup, "assets/components/demo/demo.svelte").includes("primitive-controls"))
    assert.deepEqual(rules(markup, "assets/primitives/demo/demo.svelte"), [])
  }
  assert.ok(
    rules(`${"\n".repeat(300)}<p>View</p>`, "assets/view.svelte").includes("component-size"),
  )
  assert.ok(
    !rules(`${"\n".repeat(299)}<p>View</p>`, "assets/view.svelte").includes("component-size"),
  )
  assert.deepEqual(rules(`${"\n".repeat(300)}<p>Story</p>`, "assets/view.stories.svelte"), [])
})

test("aliases and .ts are enforced for static, dynamic, export and type imports", () => {
  for (const source of [
    'import { run } from "./run.js"',
    'export { run } from "./run.js"',
    'const load = () => import("$lib/run.js")',
    'type Run = typeof import("$lib/run.js")',
  ]) {
    assert.ok(rules(source).includes("ts-imports"), source)
  }
  assert.ok(rules('import { run } from "./run.ts"').includes("alias-imports"))
  assert.deepEqual(rules('import { run } from "$lib/run.ts"'), [])
})

test("nested ternaries are refused in scripts", () => {
  assert.ok(rules("const value = a ? b : c ? d : e").includes("no-nested-ternary"))
  assert.ok(
    rules("<script>const value = a ? b : c ? d : e</script>", "assets/view.svelte").includes(
      "no-nested-ternary",
    ),
  )
  assert.deepEqual(rules("const value = a ? b : c"), [])
  assert.ok(rules("const value = a ? b : (c ? d : e)").includes("no-nested-ternary"))
  assert.ok(
    rules("<script>const value = a ? b : (c ? d : e)</script>", "assets/view.svelte").includes(
      "no-nested-ternary",
    ),
  )
})

test("Svelte and JavaScript enforce immutable parameters and explicit framework context", () => {
  for (const source of [
    "const run = (value) => { value = 2 }",
    "const run = (value) => { value++ }",
  ]) {
    assert.ok(rules(source).includes("no-parameter-assign"))
    assert.ok(
      rules(`<script>${source}</script>`, "assets/view.svelte").includes("no-parameter-assign"),
    )
  }
  assert.deepEqual(rules("const run = (value) => { const result = value + 1; return result }"), [])
  assert.deepEqual(rules("const run = (value) => { { let value = 2; value++ } return value }"), [])
  assert.ok(rules("const run = () => this.value").includes("no-this"))
})

test("never-returning arrows require a const function type to retain narrowing", () => {
  assert.ok(
    rules("const fail = (reason: string): never => { throw new Error(reason) }").includes(
      "never-function-type",
    ),
  )
  assert.deepEqual(
    rules("const fail: (reason: string) => never = (reason) => { throw new Error(reason) }"),
    [],
  )
})

test("raw controls in an embed require an explicit self-contained file registration", () => {
  const file = "assets/embeds/view.svelte"
  assert.ok(rules("<button>Run</button>", file).includes("primitive-controls"))
  assert.deepEqual(inspectFrontendSource(file, "<button>Run</button>", { embeds: [file] }), [])
  assert.ok(
    inspectFrontendSource("assets/embeds/other.svelte", "<button>Run</button>", {
      embeds: [file],
    }).some((issue) => issue.rule === "primitive-controls"),
  )
})

test("default-exported arrows are named and destructured parameters stay immutable", () => {
  assert.ok(rules("export default () => 1").includes("const-functions"))
  assert.ok(rules("const run = ({ value }) => { value = 2 }").includes("no-parameter-assign"))
  assert.ok(rules("const run = ([value]) => { value++ }").includes("no-parameter-assign"))
})

test("malformed TypeScript produces a parser diagnostic instead of a clean style result", () => {
  assert.ok(rules("const value = ;").includes("parse"))
})
