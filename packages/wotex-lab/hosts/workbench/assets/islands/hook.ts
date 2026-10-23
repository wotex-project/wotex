import { mount, tick, unmount } from "svelte"
import { decodeBase64Url } from "$lib/islands/canonical.ts"
import {
  buildEvent,
  createIslandState,
  limits,
  validateFullSnapshot,
} from "$lib/islands/protocol.ts"
import { islandLoader } from "$lib/islands/registry.ts"
import type {
  IslandInstance,
  IslandLoader,
  IslandTransport,
  JsonValue,
} from "$lib/islands/types.ts"
import { createLiveViewHook } from "$lib/live-view-hook.ts"

export interface IslandHookContext {
  el: HTMLElement
  pushEvent: (event: string, payload: unknown, reply?: (value: JsonValue) => void) => void
  pushEventTo?: (
    target: string,
    event: string,
    payload: unknown,
    reply?: (value: JsonValue) => void,
  ) => unknown
  handleEvent: (event: string, callback: (payload: unknown) => void) => unknown
  removeHandleEvent?: (reference: unknown) => void
  liveSocket?: {
    execJS?: (element: Element, command: string) => void
  }
}

export interface IslandRuntime {
  load: (name: string) => IslandLoader | undefined
  mount: typeof mount
  unmount: typeof unmount
  tick: typeof tick
}

const defaultRuntime: IslandRuntime = {
  load: islandLoader,
  mount,
  unmount,
  tick,
}

export const createIslandHook = (runtime: IslandRuntime = defaultRuntime) => {
  const controllers = new WeakMap<IslandHookContext, IslandController>()

  return createLiveViewHook<IslandHookContext>({
    mounted: async (hook) => {
      const existing = controllers.get(hook)
      if (existing) {
        await existing.refresh()
        return
      }
      const controller = createIslandController(hook, runtime)
      controllers.set(hook, controller)
      await controller.start()
    },

    updated: async (hook) => {
      await controllers.get(hook)?.refresh()
    },

    disconnected: (hook) => {
      controllers.get(hook)?.connection(false)
    },

    reconnected: (hook) => {
      controllers.get(hook)?.connection(true)
    },

    destroyed: async (hook) => {
      await controllers.get(hook)?.destroy()
      controllers.delete(hook)
    },
  })
}

type IslandController = ReturnType<typeof createIslandController>

const createIslandController = (hook: IslandHookContext, runtime: IslandRuntime) => {
  const mountRoot = hook.el
  const boundary = hook.el.closest<HTMLElement>("[data-wotex-island]")

  if (!boundary) {
    throw new Error("island mount is outside its boundary")
  }

  let instance: IslandInstance | undefined
  let state: ReturnType<typeof createIslandState> | undefined
  let connected = true
  let ready = false
  let destroyed = false
  let eventReferences: unknown[] = []
  let lastInline = ""

  const start = async () => {
    boundary.dataset.wotexIslandState = "loading"
    try {
      const encoded = mountRoot.dataset.wotexIslandSnapshot
      if (encoded) {
        if (Math.floor((encoded.length * 3) / 4) > limits.inlineSnapshotBytes) {
          throw new Error("inline island snapshot is too large")
        }
        lastInline = encoded
        await mountSnapshot(decodeBase64Url(encoded))
      } else {
        subscribe()
        requestResync()
      }
    } catch {
      if (!destroyed) {
        boundary.dataset.wotexIslandState = "failed"
      }
    }
  }

  const refresh = async () => {
    if (destroyed) {
      return
    }
    const encoded = mountRoot.dataset.wotexIslandSnapshot
    if (encoded && encoded !== lastInline) {
      lastInline = encoded
      await receiveFull(decodeBase64Url(encoded))
    }
  }

  const connection = (nextConnected: boolean) => {
    if (destroyed || nextConnected === connected) {
      return
    }
    connected = nextConnected
    ready = false
    instance?.setConnected?.(false)
    if (!connected) {
      boundary.dataset.wotexIslandState = "disconnected"
    } else {
      boundary.dataset.wotexIslandState = "loading"
      requestResync()
    }
  }

  const destroy = async () => {
    if (destroyed) {
      return
    }
    destroyed = true
    connected = false
    ready = false
    for (const reference of eventReferences) {
      hook.removeHandleEvent?.(reference)
    }
    eventReferences = []
    if (instance) {
      await runtime.unmount(instance)
    }
    instance = undefined
    boundary.dataset.wotexIslandState = "destroyed"
  }

  const subscribe = () => {
    const instanceId = mountRoot.dataset.wotexIslandInstance
    if (!instanceId || eventReferences.length > 0) {
      return
    }
    eventReferences.push(
      hook.handleEvent(`wotex:island:${instanceId}:snapshot`, (value) => receiveFull(value)),
      hook.handleEvent(`wotex:island:${instanceId}:patch`, (value) => receivePatch(value)),
    )
  }

  const requestResync = () => {
    const instanceId = mountRoot.dataset.wotexIslandInstance
    if (connected && instanceId) {
      pushHookEvent(`wotex:island:${instanceId}:resync`, {})
    }
  }

  const mountSnapshot = async (value: unknown) => {
    const snapshot = await validateFullSnapshot(value)
    if (destroyed) {
      return
    }
    if (snapshot.instance_id !== mountRoot.dataset.wotexIslandInstance) {
      throw new Error("wrong island instance")
    }
    const loader = runtime.load(snapshot.component)
    if (!loader) {
      throw new Error("unregistered island component")
    }
    const module = await loader()
    if (destroyed) {
      return
    }
    if (state) {
      await replaceSnapshot(snapshot)
      return
    }
    const transport: IslandTransport = {
      connected: () => connected && ready,

      navigate: (kind, href) => navigate(kind, href),

      push: (event, payload, commandId) => push(event, payload, commandId),
    }
    state = createIslandState(snapshot, requestResync)
    ready = connected
    instance = runtime.mount(module.default, {
      target: mountRoot,
      props: {
        payload: snapshot.payload,
        transport,
      },
    }) as IslandInstance
    subscribe()
    await runtime.tick()
    if (!destroyed) {
      boundary.dataset.wotexIslandState = "mounted"
    }
  }

  const receiveFull = async (value: unknown) => {
    if (destroyed) {
      return
    }
    try {
      if (!state) {
        await mountSnapshot(value)
      } else {
        await replaceSnapshot(value)
      }
    } catch {
      if (!destroyed) {
        boundary.dataset.wotexIslandState = "rejected"
      }
    }
  }

  const replaceSnapshot = async (value: unknown) => {
    await state?.replace(value)
    if (destroyed || !state) {
      return
    }
    instance?.update?.(state.snapshot().payload)
    ready = connected
    instance?.setConnected?.(ready)
    boundary.dataset.wotexIslandState = "mounted"
  }

  const receivePatch = async (value: unknown) => {
    if (destroyed) {
      return
    }
    const result = await state?.patch(value)
    if (!destroyed && result === "applied" && state) {
      instance?.update?.(state.snapshot().payload)
    }
  }

  const push = (event: string, payload: Record<string, JsonValue>, commandId?: string) => {
    if (destroyed || !connected || !ready || !state) {
      return Promise.reject(new Error("island is disconnected"))
    }
    const envelope = buildEvent(state.snapshot(), event, payload, commandId)
    return new Promise<JsonValue>((resolve) => {
      pushHookEvent(`wotex:island:${envelope.instance_id}:event`, envelope, resolve)
    })
  }

  const pushHookEvent = (event: string, payload: unknown, reply?: (value: JsonValue) => void) => {
    const target = mountRoot.dataset.wotexIslandTarget
    if (target && hook.pushEventTo) {
      if (reply) {
        hook.pushEventTo(target, event, payload, reply)
      } else {
        hook.pushEventTo(target, event, payload)
      }
    } else if (reply) {
      hook.pushEvent(event, payload, reply)
    } else {
      hook.pushEvent(event, payload)
    }
  }

  const navigate = (kind: "navigate" | "patch", href: string) => {
    if (destroyed) {
      return
    }
    if (!href.startsWith("/") || href.startsWith("//")) {
      throw new Error("island navigation must stay on the current origin")
    }
    const command = JSON.stringify([
      [
        kind === "patch" ? "patch" : "navigate",
        {
          href,
        },
      ],
    ])
    hook.liveSocket?.execJS?.(mountRoot, command)
  }

  return { start, refresh, connection, destroy }
}

export const WotexLabSvelteIsland = createIslandHook()
