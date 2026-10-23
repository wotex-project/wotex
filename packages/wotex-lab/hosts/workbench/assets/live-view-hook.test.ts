import assert from "node:assert/strict"
import test from "node:test"
import { createLiveViewHook } from "$lib/live-view-hook.ts"

test("LiveView's receiver reaches arrow callbacks without sharing instance context", async () => {
  const first = { events: [] as string[] }
  const second = { events: [] as string[] }
  const hook = createLiveViewHook<typeof first>({
    mounted: (context) => context.events.push("mounted"),

    updated: async (context) => {
      context.events.push("updated")
    },

    destroyed: (context) => context.events.push("destroyed"),
  })

  Reflect.apply(hook.mounted, first, [])
  Reflect.apply(hook.mounted, second, [])
  await Reflect.apply(hook.updated, first, [])
  Reflect.apply(hook.destroyed, first, [])
  assert.deepEqual(first.events, ["mounted", "updated", "destroyed"])
  assert.deepEqual(second.events, ["mounted"])
  assert.equal("disconnected" in hook, false)
})

test("hook failures propagate through the framework boundary", async () => {
  const failure = new Error("refused")
  const hook = createLiveViewHook<object>({
    mounted: () => {
      throw failure
    },

    updated: async () => {
      throw failure
    },
  })
  assert.throws(() => Reflect.apply(hook.mounted, {}, []), failure)
  await assert.rejects(Reflect.apply(hook.updated, {}, []), failure)
})
