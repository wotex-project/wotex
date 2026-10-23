import { createLiveViewHook } from "$lib/live-view-hook.ts"

interface DocumentationLinkHook {
  el: HTMLAnchorElement
  pushEvent: (event: string, payload: Record<string, never>) => void
  documentationClick?: (event: MouseEvent) => void
}

export const WotexDocumentationLink = createLiveViewHook<DocumentationLinkHook>({
  mounted: (hook) => {
    hook.documentationClick = (event) => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
        return
      }
      event.preventDefault()
      const capture = new CustomEvent("wotex:open-documentation", {
        cancelable: true,
      })
      if (window.dispatchEvent(capture)) {
        hook.pushEvent("open_documentation", {})
      }
    }
    hook.el.addEventListener("click", hook.documentationClick)
  },

  destroyed: (hook) => {
    if (hook.documentationClick) {
      hook.el.removeEventListener("click", hook.documentationClick)
    }
  },
})
