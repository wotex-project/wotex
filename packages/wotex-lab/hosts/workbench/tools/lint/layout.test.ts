import assert from "node:assert/strict"
import test from "node:test"
import { inspectComponentLayout } from "./layout.ts"

test("public and shared components require their own colocated stories", () => {
  const files = new Set([
    "assets/components/view/view.svelte",
    "assets/components/view/view.stories.ts",
  ])
  assert.deepEqual(inspectComponentLayout("assets/components/view/view.svelte", files), [])
  assert.ok(inspectComponentLayout("assets/components/view/missing.svelte", files).length > 0)
  files.add("assets/components/view/shared.stories.ts")
  assert.deepEqual(inspectComponentLayout("assets/components/view/shared.svelte", files), [])
})

test("private children are covered by their existing parent surface and catalogue examples stay separate", () => {
  const files = new Set([
    "assets/components/view/view.svelte",
    "assets/components/view/view.stories.ts",
  ])
  assert.deepEqual(inspectComponentLayout("assets/components/view/view/row.svelte", files), [])
  assert.ok(inspectComponentLayout("assets/components/view/other/row.svelte", files).length > 0)
  assert.deepEqual(inspectComponentLayout("assets/catalogue/example/example.svelte", files), [])
})
