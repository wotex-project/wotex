import assert from "node:assert/strict"
import test from "node:test"
import { nextItemIndex } from "$lib/primitives/menu-navigation.ts"

test("keyboard movement wraps only the supplied enabled items", () => {
  assert.equal(nextItemIndex("ArrowDown", 1, 2), 0)
  assert.equal(nextItemIndex("ArrowUp", 0, 2), 1)
  assert.equal(nextItemIndex("ArrowRight", 0, 2), 1)
  assert.equal(nextItemIndex("ArrowLeft", 1, 2), 0)
  assert.equal(nextItemIndex("Home", 1, 2), 0)
  assert.equal(nextItemIndex("End", 0, 2), 1)
})

test("unknown focus enters at an endpoint and empty or non-navigation input is inert", () => {
  assert.equal(nextItemIndex("ArrowDown", -1, 3), 0)
  assert.equal(nextItemIndex("ArrowUp", -1, 3), 2)
  assert.equal(nextItemIndex("Home", 0, 0), null)
  for (const key of ["Enter", " ", "Escape", "Tab"]) {
    assert.equal(nextItemIndex(key, 0, 3), null)
  }
})
