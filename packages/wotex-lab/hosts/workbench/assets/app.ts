import "./islands/design-system.css"
import { WotexDocumentationLink } from "./documentation-link.js"
import { WotexLabSvelteIsland } from "./islands/hook.js"
import {
  observeLayoutProfileWithin,
  preserveShellFocusWithin,
} from "./layout-profile.js"

interface PhoenixSocketConstructor {
  new (path: string, options?: Record<string, unknown>): unknown
}

interface LiveSocketInstance {
  connect: () => void
  disconnect: () => void
  isConnected: () => boolean
}

interface LiveSocketConstructor {
  new (
    path: string,
    socket: PhoenixSocketConstructor,
    options: Record<string, unknown>,
  ): LiveSocketInstance
}

declare global {
  interface Window {
    LiveView?: { LiveSocket: LiveSocketConstructor }
    Phoenix?: { Socket: PhoenixSocketConstructor }
    liveSocket?: LiveSocketInstance
  }
}

const csrf = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content
interface BoardSearchHook { el: HTMLElement; hadFocus?: boolean }
const WotexBoardSearch = {
  mounted(this: BoardSearchHook) {
    const target = this.el.dataset.focusTarget
    if (target) this.el.querySelector<HTMLElement>(target)?.focus({ preventScroll: true })
  },
  beforeUpdate(this: BoardSearchHook) {
    this.hadFocus = this.el.contains(document.activeElement)
  },
  updated(this: BoardSearchHook) {
    if (this.hadFocus && document.activeElement === document.body)
      this.el.querySelector<HTMLElement>("#wl-board-search-query")?.focus({ preventScroll: true })
  },
}
if (document.body) {
  const stopObservingLayout = observeLayoutProfileWithin(document.body)
  const stopPreservingFocus = preserveShellFocusWithin(document.body)
  const searchKeys = (event: KeyboardEvent) => {
    if (event.defaultPrevented || event.isComposing || event.altKey) return
    const trigger = document.querySelector<HTMLButtonElement>(".wl-shell-canvas #wl-board-search")
    if (trigger && !event.shiftKey && (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      const input = document.querySelector<HTMLInputElement>("#wl-board-search-query")
      if (input) input.focus({ preventScroll: true })
      else trigger.click()
      return
    }
    const target = event.target
    if (!(target instanceof HTMLElement) || !target.closest("#wl-board-search-content")) return
    const input = target.matches("#wl-board-search-query")
    if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key) ||
        (input && ["Home", "End"].includes(event.key))) return
    const results = [...document.querySelectorAll<HTMLButtonElement>("#wl-board-search-results button")]
    if (results.length === 0) return
    event.preventDefault()
    const current = results.indexOf(target as HTMLButtonElement)
    const next = event.key === "Home" ? 0 : event.key === "End" ? results.length - 1 :
      input ? (event.key === "ArrowDown" ? 0 : results.length - 1) :
        (current + (event.key === "ArrowDown" ? 1 : results.length - 1)) % results.length
    results[next]?.focus()
  }
  window.addEventListener("keydown", searchKeys)
  const clearBoardSearch = () => {
    const input = document.querySelector<HTMLInputElement>("#wl-board-search-panel #wl-board-search-query")
    if (input) {
      input.value = ""
      input.focus({ preventScroll: true })
    }
  }
  window.addEventListener("wotex:clear-board-search", clearBoardSearch)
  window.addEventListener(
    "pagehide",
    () => {
      stopObservingLayout()
      stopPreservingFocus()
      window.removeEventListener("keydown", searchKeys)
      window.removeEventListener("wotex:clear-board-search", clearBoardSearch)
    },
    { once: true },
  )
}

if (window.Phoenix && window.LiveView && csrf) {
  const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    hooks: { WotexLabSvelteIsland, WotexDocumentationLink, WotexBoardSearch },
    params: { _csrf_token: csrf },
  })

  liveSocket.connect()
  window.liveSocket = liveSocket
}
