import assert from "node:assert/strict"
import { createRequire } from "node:module"
import test from "node:test"

const requirePlugin = createRequire(import.meta.resolve("@sveltejs/vite-plugin-svelte"))
const merge = requirePlugin("deepmerge") as (
  target: object,
  source: object,
) => Record<string, unknown>

test("the installed Svelte merger cannot change a result prototype from either input", () => {
  const poison = JSON.parse('{"__proto__":{"inheritedFlag":true}}')
  const targets = [Object.create(null), poison, { nested: null }]
  const sources = [poison, {}, { nested: poison }]

  for (const target of targets) {
    for (const source of sources) {
      const result = merge(target, source)
      assert.equal(Object.getPrototypeOf(result), Object.prototype)
      assert.equal(result.inheritedFlag, undefined)
      if (result.nested && typeof result.nested === "object") {
        assert.equal(Object.getPrototypeOf(result.nested), Object.prototype)
        assert.equal(Reflect.get(result.nested, "inheritedFlag"), undefined)
      }
    }
  }
})

test("the installed Svelte merger preserves nested values and configured array replacement", () => {
  const configuredMerge = requirePlugin("deepmerge")
  assert.deepEqual(
    configuredMerge(
      { compilerOptions: { dev: false }, preprocess: ["old"] },
      { compilerOptions: { css: "external" }, preprocess: ["new"] },
      { arrayMerge: (_target: unknown[], source: unknown[]) => source },
    ),
    { compilerOptions: { dev: false, css: "external" }, preprocess: ["new"] },
  )
})
