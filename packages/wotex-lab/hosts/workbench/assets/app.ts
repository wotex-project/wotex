import { createLiveViewHook } from "$lib/live-view-hook.ts"
import "$lib/islands/design-system.css"
import { WotexDocumentationLink } from "$lib/documentation-link.ts"
import { WotexLabSvelteIsland } from "$lib/islands/hook.ts"
import { observeLayoutProfileWithin, preserveShellFocusWithin } from "$lib/layout-profile.ts"

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
    LiveView?: {
      LiveSocket: LiveSocketConstructor
    }
    Phoenix?: {
      Socket: PhoenixSocketConstructor
    }
    liveSocket?: LiveSocketInstance
  }
}

const csrf = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content
interface BoardSearchHook {
  el: HTMLElement
  hadFocus?: boolean
}

const WotexBoardSearch = createLiveViewHook<BoardSearchHook>({
  mounted: (hook) => {
    const target = hook.el.dataset.focusTarget
    if (target) {
      hook.el.querySelector<HTMLElement>(target)?.focus({
        preventScroll: true,
      })
    }
  },

  beforeUpdate: (hook) => {
    hook.hadFocus = hook.el.contains(document.activeElement)
  },

  updated: (hook) => {
    if (hook.hadFocus && document.activeElement === document.body) {
      hook.el.querySelector<HTMLElement>("#wl-board-search-query")?.focus({
        preventScroll: true,
      })
    }
  },
})

const boardSearchResultIndex = (key: string, current: number, count: number, inQuery: boolean) => {
  if (key === "Home") {
    return 0
  }
  if (key === "End") {
    return count - 1
  }
  const forward = key === "ArrowDown"
  if (inQuery) {
    return forward ? 0 : count - 1
  }
  return (current + (forward ? 1 : count - 1)) % count
}

const moveBoardSearchFocus = (event: KeyboardEvent) => {
  const target = event.target
  if (!(target instanceof HTMLElement) || !target.closest("#wl-board-search-content")) {
    return
  }
  const inQuery = target.matches("#wl-board-search-query")
  if (
    !["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key) ||
    (inQuery && ["Home", "End"].includes(event.key))
  ) {
    return
  }
  const results = [
    ...document.querySelectorAll<HTMLButtonElement>("#wl-board-search-results button"),
  ]
  if (results.length === 0) {
    return
  }
  event.preventDefault()
  const current = target instanceof HTMLButtonElement ? results.indexOf(target) : -1
  const next = boardSearchResultIndex(event.key, current, results.length, inQuery)
  results[next]?.focus()
}

if (document.body) {
  const stopObservingLayout = observeLayoutProfileWithin(document.body)
  const stopPreservingFocus = preserveShellFocusWithin(document.body)

  const searchKeys = (event: KeyboardEvent) => {
    if (event.defaultPrevented || event.isComposing || event.altKey) {
      return
    }
    const trigger = document.querySelector<HTMLButtonElement>(".wl-shell-canvas #wl-board-search")
    if (
      trigger &&
      !event.shiftKey &&
      (event.metaKey || event.ctrlKey) &&
      event.key.toLowerCase() === "k"
    ) {
      event.preventDefault()
      const input = document.querySelector<HTMLInputElement>("#wl-board-search-query")
      if (input) {
        input.focus({
          preventScroll: true,
        })
      } else {
        trigger.click()
      }
      return
    }
    moveBoardSearchFocus(event)
  }

  window.addEventListener("keydown", searchKeys)

  const clearBoardSearch = () => {
    const input = document.querySelector<HTMLInputElement>(
      "#wl-board-search-panel #wl-board-search-query",
    )
    if (input) {
      input.value = ""
      input.focus({
        preventScroll: true,
      })
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
    {
      once: true,
    },
  )
}

if (window.Phoenix && window.LiveView && csrf) {
  const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    hooks: {
      WotexLabSvelteIsland,
      WotexDocumentationLink,
      WotexBoardSearch,
    },
    params: {
      _csrf_token: csrf,
    },
  })

  liveSocket.connect()
  window.liveSocket = liveSocket
}
