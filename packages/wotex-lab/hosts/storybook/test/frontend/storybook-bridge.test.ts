import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import { runInNewContext } from "node:vm"
import { createLiveViewHook } from "$lib/live-view-hook.ts"

const source = readFileSync(
  new URL("../../priv/static/contract-assets/storybook-loader.js", import.meta.url),
  "utf8",
)

test("standalone Storybook bridge keeps lazy loading and lifecycle receiver state per mount", async () => {
  const events: { name: string; context: object }[] = []

  const record = (name: string) => (context: object) => {
    events.push({ name, context })
  }

  const delegate = createLiveViewHook({
    mounted: record("mounted"),
    updated: record("updated"),
    disconnected: record("disconnected"),
    reconnected: record("reconnected"),
    destroyed: record("destroyed"),
  })
  const window = { storybook: { Hooks: { WotexLabSvelteIsland: delegate } } }
  let loads = 0

  const loadModule = async () => {
    loads += 1
    window.storybook.Hooks.WotexLabSvelteIsland = delegate
  }

  // Replace only the external module port; execute the shipped bridge itself.
  const importCall = 'import("/contract-assets/storybook-module.js")'
  assert.equal(source.split(importCall).length, 2)
  runInNewContext(source.replace(importCall, "loadModule()"), { window, loadModule })
  const bridge = window.storybook.Hooks.WotexLabSvelteIsland
  const first = {}
  const second = {}
  await Reflect.apply(bridge.mounted, first, [])
  await Reflect.apply(bridge.mounted, first, [])
  await Reflect.apply(bridge.mounted, second, [])
  for (const name of ["updated", "disconnected", "reconnected", "destroyed"]) {
    await Reflect.apply(bridge[name], first, [])
  }
  assert.equal(loads, 2)
  assert.deepEqual(
    events.map(({ name }) => name),
    ["mounted", "mounted", "mounted", "updated", "disconnected", "reconnected", "destroyed"],
  )
  assert.equal(events[2].context, second)
  assert.ok(events.filter((_, index) => index !== 2).every(({ context }) => context === first))
})
