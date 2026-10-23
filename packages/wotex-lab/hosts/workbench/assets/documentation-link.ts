interface DocumentationLinkHook {
  el: HTMLAnchorElement
  pushEvent: (event: string, payload: Record<string, never>) => void
  documentationClick?: (event: MouseEvent) => void
}

export const WotexDocumentationLink = {
  mounted(this: DocumentationLinkHook) {
    this.documentationClick = (event) => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
        return
      }
      event.preventDefault()
      const capture = new CustomEvent("wotex:open-documentation", {
        cancelable: true,
      })
      if (window.dispatchEvent(capture)) {
        this.pushEvent("open_documentation", {})
      }
    }
    this.el.addEventListener("click", this.documentationClick)
  },
  destroyed(this: DocumentationLinkHook) {
    if (this.documentationClick) {
      this.el.removeEventListener("click", this.documentationClick)
    }
  },
}
