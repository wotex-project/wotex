import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import { createIslandHook, type IslandHookContext, type IslandRuntime } from "$lib/islands/hook.ts"
import type { FullSnapshot, IslandModule, IslandTransport, JsonValue } from "$lib/islands/types.ts"

const snapshot = (
  JSON.parse(
    readFileSync(new URL("../../test/support/island_protocol.json", import.meta.url), "utf8"),
  ) as { transition: { snapshot: FullSnapshot } }
).transition.snapshot

const fixture = () => {
  const boundary = { dataset: {} as Record<string, string> }
  const handlers = new Map<string, (value: unknown) => void>()
  const events: { name: string; payload: unknown }[] = []
  const connected: boolean[] = []
  const readiness: (() => void)[] = []
  let mounts = 0
  let unmounts = 0
  let transport: IslandTransport | undefined
  const instance = {
    update: () => undefined,

    setConnected: (value: boolean) => {
      connected.push(value)
      if (value) {
        readiness.splice(0).forEach((ready) => {
          ready()
        })
      }
    },
  }
  const element = {
    dataset: {
      wotexIslandSnapshot: Buffer.from(JSON.stringify(snapshot)).toString("base64url"),
      wotexIslandInstance: snapshot.instance_id,
    },

    closest: () => boundary,
  }
  const context = {
    el: element,

    pushEvent: (name: string, payload: unknown, reply?: (value: JsonValue) => void) => {
      events.push({ name, payload })
      reply?.({ status: "accepted" })
    },

    handleEvent: (name: string, callback: (value: unknown) => void) => {
      handlers.set(name, callback)
      return name
    },

    removeHandleEvent: (name: string) => {
      handlers.delete(name)
    },
  } as unknown as IslandHookContext
  const runtime = {
    load: () => async () => ({ default: () => undefined }),

    mount: (_component: unknown, options: { props: { transport: IslandTransport } }) => {
      mounts += 1
      transport = options.props.transport
      return instance
    },

    unmount: async () => {
      unmounts += 1
    },

    tick: async () => undefined,
  } as unknown as IslandRuntime

  return {
    boundary,
    context,
    runtime,
    handlers,
    events,
    connected,
    instance,

    whenConnected: () =>
      new Promise<void>((resolve) => {
        readiness.push(resolve)
      }),

    transport: () => {
      assert.ok(transport)
      return transport
    },

    counts: () => ({ mounts, unmounts }),
  }
}

test("mount/reconnect resynchronizes once, gates commands and destroys only its own handlers", async () => {
  const state = fixture()
  const hook = createIslandHook(state.runtime)
  await Reflect.apply(hook.mounted, state.context, [])
  await Reflect.apply(hook.mounted, state.context, [])
  assert.equal(state.boundary.dataset.wotexIslandState, "mounted")
  assert.equal(state.handlers.size, 2)
  assert.equal(state.counts().mounts, 1)

  Reflect.apply(hook.disconnected, state.context, [])
  assert.equal(state.transport().connected(), false)
  await assert.rejects(state.transport().push("select", { key: "one" }), /disconnected/)
  Reflect.apply(hook.reconnected, state.context, [])
  assert.equal(state.events.length, 1)
  assert.equal(state.events[0].name, `wotex:island:${snapshot.instance_id}:resync`)
  assert.equal(state.transport().connected(), false)

  const resynchronized = state.whenConnected()
  state.handlers.get(`wotex:island:${snapshot.instance_id}:snapshot`)?.(snapshot)
  await resynchronized
  assert.equal(state.transport().connected(), true)
  await state.transport().push("select", { key: "one" })
  assert.equal(state.events.length, 2)

  const lateSnapshot = state.handlers.get(`wotex:island:${snapshot.instance_id}:snapshot`)
  const latePatch = state.handlers.get(`wotex:island:${snapshot.instance_id}:patch`)
  await Reflect.apply(hook.destroyed, state.context, [])
  await Reflect.apply(hook.destroyed, state.context, [])
  assert.equal(state.transport().connected(), false)
  await assert.rejects(state.transport().push("select", { key: "one" }), /disconnected/)
  await lateSnapshot?.(snapshot)
  await latePatch?.({})
  assert.deepEqual(state.counts(), { mounts: 1, unmounts: 1 })
  assert.equal(state.handlers.size, 0)
  assert.equal(state.boundary.dataset.wotexIslandState, "destroyed")
})

test("two mounts keep independent transports, event registrations and cleanup", async () => {
  const first = fixture()
  const second = fixture()
  const mount = first.runtime.mount
  first.runtime.mount = ((component, options) =>
    options.target === first.context.el
      ? mount(component, options)
      : second.runtime.mount(component, options)) as IslandRuntime["mount"]
  const hook = createIslandHook(first.runtime)
  await Reflect.apply(hook.mounted, first.context, [])
  await Reflect.apply(hook.mounted, second.context, [])
  Reflect.apply(hook.disconnected, first.context, [])
  assert.equal(second.transport().connected(), true)
  await Reflect.apply(hook.destroyed, first.context, [])
  assert.equal(first.handlers.size, 0)
  assert.equal(second.handlers.size, 2)
  await Reflect.apply(hook.destroyed, second.context, [])
})

test("destroying an island while its chunk loads prevents a late mount", async () => {
  const state = fixture()
  let release: (() => void) | undefined
  let signalLoading: (() => void) | undefined
  const loading = new Promise<void>((resolve) => {
    signalLoading = resolve
  })
  const loaded = new Promise<void>((resolve) => {
    release = resolve
  })
  state.runtime.load = () => async () => {
    signalLoading?.()
    await loaded
    return { default: () => undefined } as unknown as IslandModule
  }
  const hook = createIslandHook(state.runtime)
  const pending = Reflect.apply(hook.mounted, state.context, [])
  await loading
  await Reflect.apply(hook.destroyed, state.context, [])
  release?.()
  await pending
  assert.deepEqual(state.counts(), { mounts: 0, unmounts: 0 })
  assert.equal(state.boundary.dataset.wotexIslandState, "destroyed")
})

test("an invalid initial snapshot stays failed without allocating a component", async () => {
  const state = fixture()
  state.context.el.dataset.wotexIslandSnapshot = "invalid"
  const hook = createIslandHook(state.runtime)
  await Reflect.apply(hook.mounted, state.context, [])
  assert.equal(state.boundary.dataset.wotexIslandState, "failed")
  assert.equal(state.counts().mounts, 0)
  assert.equal(state.handlers.size, 0)
  await Reflect.apply(hook.destroyed, state.context, [])
})

test("concurrent initial snapshots share one mounted component", async () => {
  const state = fixture()
  state.context.el.dataset.wotexIslandSnapshot = ""
  let release: (() => void) | undefined
  let signalLoading: (() => void) | undefined
  let loads = 0
  const loading = new Promise<void>((resolve) => {
    signalLoading = resolve
  })
  const loaded = new Promise<void>((resolve) => {
    release = resolve
  })
  state.runtime.load = () => async () => {
    loads += 1
    if (loads === 2) {
      signalLoading?.()
    }
    await loaded
    return { default: () => undefined } as unknown as IslandModule
  }
  const hook = createIslandHook(state.runtime)
  await Reflect.apply(hook.mounted, state.context, [])
  const receive = state.handlers.get(`wotex:island:${snapshot.instance_id}:snapshot`)
  assert.ok(receive)
  const first = receive(snapshot)
  const second = receive(snapshot)
  await loading
  release?.()
  await Promise.all([first, second])
  assert.equal(state.counts().mounts, 1)
  assert.equal(state.boundary.dataset.wotexIslandState, "mounted")
  await Reflect.apply(hook.destroyed, state.context, [])
  assert.equal(state.counts().unmounts, 1)
})
