import { mount, tick, unmount } from "svelte"
import { decodeBase64Url } from "./canonical.js"
import { buildEvent, IslandState, limits, validateFullSnapshot } from "./protocol.js"
import { islandLoader } from "./registry.js"
import type { IslandInstance, IslandLoader, IslandTransport, JsonValue } from "./types.js"

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
  liveSocket?: { execJS?: (element: Element, command: string) => void }
}

export interface IslandRuntime {
  load: (name: string) => IslandLoader | undefined
  mount: typeof mount
  unmount: typeof unmount
  tick: typeof tick
}

const defaultRuntime: IslandRuntime = { load: islandLoader, mount, unmount, tick }

export const createIslandHook = (runtime: IslandRuntime = defaultRuntime) => ({
  async mounted(this: IslandHookContext & { wotexIsland?: HookState }) {
    if (this.wotexIsland) {
      await this.wotexIsland.refresh()
      return
    }
    this.wotexIsland = new HookState(this, runtime)
    await this.wotexIsland.start()
  },
  async updated(this: IslandHookContext & { wotexIsland?: HookState }) {
    await this.wotexIsland?.refresh()
  },
  disconnected(this: IslandHookContext & { wotexIsland?: HookState }) {
    this.wotexIsland?.connection(false)
  },
  reconnected(this: IslandHookContext & { wotexIsland?: HookState }) {
    this.wotexIsland?.connection(true)
  },
  async destroyed(this: IslandHookContext & { wotexIsland?: HookState }) {
    await this.wotexIsland?.destroy()
    this.wotexIsland = undefined
  },
})

class HookState {
  readonly #hook: IslandHookContext
  readonly #runtime: IslandRuntime
  readonly #mountRoot: HTMLElement
  readonly #boundary: HTMLElement
  #instance?: IslandInstance
  #state?: IslandState
  #connected = true
  #ready = false
  #destroyed = false
  #eventReferences: unknown[] = []
  #lastInline = ""

  constructor(hook: IslandHookContext, runtime: IslandRuntime) {
    this.#hook = hook
    this.#runtime = runtime
    this.#mountRoot = hook.el
    const boundary = hook.el.closest<HTMLElement>("[data-wotex-island]")
    if (!boundary) throw new Error("island mount is outside its boundary")
    this.#boundary = boundary
  }

  async start() {
    this.#boundary.dataset.wotexIslandState = "loading"
    try {
      const encoded = this.#mountRoot.dataset.wotexIslandSnapshot
      if (encoded) {
        if (Math.floor((encoded.length * 3) / 4) > limits.inlineSnapshotBytes)
          throw new Error("inline island snapshot is too large")
        this.#lastInline = encoded
        await this.mountSnapshot(decodeBase64Url(encoded))
      } else {
        this.subscribe()
        this.requestResync()
      }
    } catch {
      this.#boundary.dataset.wotexIslandState = "failed"
    }
  }

  async refresh() {
    if (this.#destroyed) return
    const encoded = this.#mountRoot.dataset.wotexIslandSnapshot
    if (encoded && encoded !== this.#lastInline) {
      this.#lastInline = encoded
      await this.receiveFull(decodeBase64Url(encoded))
    }
  }

  connection(connected: boolean) {
    if (this.#destroyed || connected === this.#connected) return
    this.#connected = connected
    this.#ready = false
    this.#instance?.setConnected?.(false)
    if (!connected) this.#boundary.dataset.wotexIslandState = "disconnected"
    else {
      this.#boundary.dataset.wotexIslandState = "loading"
      this.requestResync()
    }
  }

  async destroy() {
    if (this.#destroyed) return
    this.#destroyed = true
    for (const reference of this.#eventReferences) this.#hook.removeHandleEvent?.(reference)
    this.#eventReferences = []
    if (this.#instance) await this.#runtime.unmount(this.#instance)
    this.#instance = undefined
    this.#boundary.dataset.wotexIslandState = "destroyed"
  }

  private subscribe() {
    const instance = this.#mountRoot.dataset.wotexIslandInstance
    if (!instance || this.#eventReferences.length > 0) return
    this.#eventReferences.push(
      this.#hook.handleEvent(
        `wotex:island:${instance}:snapshot`,
        (value) => void this.receiveFull(value),
      ),
      this.#hook.handleEvent(
        `wotex:island:${instance}:patch`,
        (value) => void this.receivePatch(value),
      ),
    )
  }

  private requestResync = () => {
    const instance = this.#mountRoot.dataset.wotexIslandInstance
    if (this.#connected && instance) this.pushHookEvent(`wotex:island:${instance}:resync`, {})
  }

  private async mountSnapshot(value: unknown) {
    const snapshot = await validateFullSnapshot(value)
    if (snapshot.instance_id !== this.#mountRoot.dataset.wotexIslandInstance)
      throw new Error("wrong island instance")
    const loader = this.#runtime.load(snapshot.component)
    if (!loader) throw new Error("unregistered island component")
    const module = await loader()
    if (this.#destroyed) return
    const transport: IslandTransport = {
      connected: () => this.#connected && this.#ready,
      navigate: (kind, href) => this.navigate(kind, href),
      push: (event, payload, commandId) => this.push(event, payload, commandId),
    }
    this.#state = new IslandState(snapshot, this.requestResync)
    this.#ready = this.#connected
    this.#instance = this.#runtime.mount(module.default, {
      target: this.#mountRoot,
      props: { payload: snapshot.payload, transport },
    }) as IslandInstance
    this.subscribe()
    await this.#runtime.tick()
    if (!this.#destroyed) this.#boundary.dataset.wotexIslandState = "mounted"
  }

  private async receiveFull(value: unknown) {
    try {
      if (!this.#state) await this.mountSnapshot(value)
      else {
        await this.#state.replace(value)
        this.#instance?.update?.(this.#state.snapshot.payload)
        this.#ready = this.#connected
        this.#instance?.setConnected?.(this.#ready)
        this.#boundary.dataset.wotexIslandState = "mounted"
      }
    } catch {
      this.#boundary.dataset.wotexIslandState = "rejected"
    }
  }

  private async receivePatch(value: unknown) {
    const result = await this.#state?.patch(value)
    if (result === "applied" && this.#state) this.#instance?.update?.(this.#state.snapshot.payload)
  }

  private push(event: string, payload: Record<string, JsonValue>, commandId?: string) {
    if (!this.#connected || !this.#ready || !this.#state)
      return Promise.reject(new Error("island is disconnected"))
    const envelope = buildEvent(this.#state.snapshot, event, payload, commandId)
    return new Promise<JsonValue>((resolve) => {
      this.pushHookEvent(`wotex:island:${envelope.instance_id}:event`, envelope, resolve)
    })
  }

  private pushHookEvent(event: string, payload: unknown, reply?: (value: JsonValue) => void) {
    const target = this.#mountRoot.dataset.wotexIslandTarget
    if (target && this.#hook.pushEventTo) {
      if (reply) this.#hook.pushEventTo(target, event, payload, reply)
      else this.#hook.pushEventTo(target, event, payload)
    } else if (reply) this.#hook.pushEvent(event, payload, reply)
    else this.#hook.pushEvent(event, payload)
  }

  private navigate(kind: "navigate" | "patch", href: string) {
    if (!href.startsWith("/") || href.startsWith("//"))
      throw new Error("island navigation must stay on the current origin")
    const command = JSON.stringify([[kind === "patch" ? "patch" : "navigate", { href }]])
    this.#hook.liveSocket?.execJS?.(this.#mountRoot, command)
  }
}

export const WotexLabSvelteIsland = createIslandHook()
