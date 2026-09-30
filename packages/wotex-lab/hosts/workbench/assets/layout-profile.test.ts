import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { layoutProfileForWidth } from "./layout-profile.ts"

describe("layoutProfileForWidth", () => {
  for (const [width, expected] of [
    [599, "compact"],
    [599.5, "compact"],
    [600, "medium"],
    [839, "medium"],
    [839.5, "medium"],
    [840, "expanded"],
  ] as const) {
    it(`maps ${width} CSS pixels to ${expected}`, () => {
      assert.equal(layoutProfileForWidth(width), expected)
    })
  }
})
