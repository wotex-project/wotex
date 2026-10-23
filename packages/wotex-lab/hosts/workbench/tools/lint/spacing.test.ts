import assert from "node:assert/strict"
import test from "node:test"
import { formatSpacing, spacingPositions } from "./spacing.ts"

test("imports, types, functions and test/lifecycle groups have blank lines", () => {
  for (const source of [
    'import { value } from "library"\nconst other = value\n',
    "type First = string\ntype Second = number\nconst value = 1\n",
    "const first = () => 1\nconst second = () => 2\n",
    'test("one", () => {})\ntest("two", () => {})\n',
    "onMount(() => {})\nonDestroy(() => {})\n",
  ]) {
    const formatted = formatSpacing("example.ts", source)
    assert.notEqual(formatted, source)
    assert.deepEqual(spacingPositions("example.ts", formatted), [])
    assert.equal(formatSpacing("example.ts", formatted), formatted)
  }
})

test("multi-line object operations and accessors separate while compact members stay compact", () => {
  const source =
    "const state = {\n  get value() {\n    return current\n  },\n  set value(next) {\n    current = next\n  },\n  save: () => {\n    persist()\n  },\n}\n"
  const formatted = formatSpacing("example.ts", source)
  assert.ok(formatted.includes("},\n\n  set value"))
  assert.ok(formatted.includes("},\n\n  save"))
  const compact =
    "const state = {\n  get value() { return current },\n  set value(next) { current = next },\n  save: () => persist(),\n}\n"
  assert.equal(formatSpacing("example.ts", compact), compact)
})

test("spacing preserves comments, markup and strings and works in both Svelte scripts", () => {
  const body = 'const first = () => "a\\nb"\n// next operation\nconst second = () => 2\n'
  const source = `<script module>\n${body}</script>\n<script>\n${body}</script>\n<p>Keep  this</p>`
  const formatted = formatSpacing("view.svelte", source)
  assert.ok(formatted.includes("// next operation\nconst second"))
  assert.ok(formatted.endsWith("<p>Keep  this</p>"))
  assert.ok(formatted.includes('"a\\nb"'))
  assert.deepEqual(spacingPositions("view.svelte", formatted), [])
  assert.equal(formatSpacing("view.svelte", formatted), formatted)
})
