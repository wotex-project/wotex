import assert from "node:assert/strict"
import test from "node:test"
import ts from "typescript"
import { inspectOrdering } from "./ordering.ts"

const findings = (source: string) =>
  inspectOrdering(ts.createSourceFile("example.ts", source, ts.ScriptTarget.Latest, true))

test("direct, transitive and aliased eager calls detect a later arrow binding", () => {
  for (const source of [
    "later(); const later = () => 1",
    "const run = () => later(); const value = run(); const later = () => 1",
    "const first = () => second(); const second = () => later(); first(); const later = () => 1",
    "const run = () => later(); const alias = run; alias(); const later = () => 1",
    "const other = () => 1; const run = () => later(); run(); const later = other",
    "const actions = { run: () => later() }; actions.run(); const later = () => 1",
    "const value = (() => later())(); const later = () => 1",
  ]) {
    assert.ok(
      findings(source).some((issue) => issue.name === "later"),
      source,
    )
  }
})

test("synchronous callbacks are followed, including named callbacks", () => {
  for (const source of [
    "const value = [1].map(() => later()); const later = () => 1",
    "const map = () => later(); const value = [1].map(map); const later = () => 1",
    "const run = () => [1].forEach(() => later()); run(); const later = () => 1",
  ]) {
    assert.ok(
      findings(source).some((issue) => issue.name === "later"),
      source,
    )
  }
})

test("lifecycle, derived, timer, event, promise and test callbacks are deferred", () => {
  for (const call of [
    "$effect",
    "$derived.by",
    "onMount",
    "onDestroy",
    "setTimeout",
    "setInterval",
    "queueMicrotask",
    "requestAnimationFrame",
    "window.addEventListener",
    "hook.handleEvent",
    "promise.then",
    "promise.catch",
    "promise.finally",
    "test",
    "test.skip",
    "describe",
    "beforeEach",
  ]) {
    assert.deepEqual(findings(`${call}(() => later()); const later = () => 1`), [], call)
  }
  assert.ok(findings("onMount(later); const later = () => 1").length > 0)
  assert.ok(findings("const value = $derived(later()); const later = () => 1").length > 0)
})

test("nested blocks and local function bodies have independent statement ordering", () => {
  assert.ok(findings("{ const run = () => later(); run(); const later = () => 1 }").length > 0)
  assert.ok(findings("const factory = () => { run(); const run = () => 1 }").length > 0)
  assert.deepEqual(findings("const factory = () => { const run = () => 1; return run() }"), [])
  assert.deepEqual(findings("const first = () => second(); const second = () => 1; first()"), [])
})

test("parameter and local shadowing do not resolve to an unrelated outer arrow", () => {
  assert.deepEqual(
    findings("const run = (later) => later(); run(() => 1); const later = () => 2"),
    [],
  )
  assert.deepEqual(findings("{ const later = 1; const value = later } const later = () => 2"), [])
  assert.ok(
    findings(
      "const run = () => later(); const invoke = (later) => run(); invoke(() => 1); const later = () => 2",
    ).length > 0,
  )
})

test("recursion terminates and type/member names are not evaluated as bindings", () => {
  assert.deepEqual(findings("const run = () => run(); run()"), [])
  assert.deepEqual(
    findings("const object = { later: 1 }; const value = object.later; const later = () => 2"),
    [],
  )
  assert.deepEqual(findings("type Alias = typeof later; const later = () => 2"), [])
})

test("local helpers and parameters with lifecycle names do not receive a deferred exemption", () => {
  assert.ok(
    findings(
      "const onMount = (callback) => callback(); onMount(() => later()); const later = () => 1",
    ).length > 0,
  )
  assert.ok(
    findings(
      "const invoke = (onMount) => onMount(() => later()); invoke((callback) => callback()); const later = () => 1",
    ).length > 0,
  )
})
