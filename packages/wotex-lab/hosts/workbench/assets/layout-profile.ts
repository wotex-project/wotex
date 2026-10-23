export const layoutProfileThresholds = {
  compactUpperBound: 600,
  mediumUpperBound: 840,
} as const

export type LayoutProfile = "compact" | "medium" | "expanded"

export const layoutProfileForWidth = (width: number): LayoutProfile => {
  if (width < layoutProfileThresholds.compactUpperBound) {
    return "compact"
  }
  if (width < layoutProfileThresholds.mediumUpperBound) {
    return "medium"
  }
  return "expanded"
}

export const observeLayoutProfile = (content: HTMLElement): (() => void) => {
  const shell = content.closest<HTMLElement>(".wotex-lab")
  const observer = new ResizeObserver(([entry]) => {
    if (!entry) {
      return
    }

    const profile = layoutProfileForWidth(entry.contentRect.width)
    content.dataset.layoutProfile = profile
    if (shell) {
      shell.dataset.layoutProfile = profile
    }
  })

  observer.observe(content)
  return () => observer.disconnect()
}

export const observeLayoutProfileWithin = (root: ParentNode): (() => void) => {
  let content: HTMLElement | null = null

  const contentObserver = { stop: () => {} }

  const bindCurrentContent = () => {
    const nextContent = root.querySelector<HTMLElement>(".wotex-lab .wl-main")
    const profile = nextContent?.dataset.layoutProfile
    const shellProfile = nextContent?.closest<HTMLElement>(".wotex-lab")?.dataset.layoutProfile
    if (nextContent === content && (!nextContent || (profile && profile === shellProfile))) {
      return
    }

    contentObserver.stop()
    content = nextContent
    if (content) {
      contentObserver.stop = observeLayoutProfile(content)
    } else {
      contentObserver.stop = () => {}
    }
  }

  const observer = new MutationObserver(bindCurrentContent)
  observer.observe(root, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["data-layout-profile"],
  })
  bindCurrentContent()

  return () => {
    observer.disconnect()
    contentObserver.stop()
  }
}

export const preserveShellFocusAcrossProfiles = (shell: HTMLElement): (() => void) => {
  let compact = shell.getBoundingClientRect().width < layoutProfileThresholds.mediumUpperBound
  let focusedToggle = false

  const recordFocus = (event: FocusEvent) => {
    const target = event.target
    if (!(target instanceof Element) || target === document.body) {
      return
    }
    focusedToggle = target.matches(".wl-topbar > .wl-icon-button")
  }

  const observer = new ResizeObserver(([entry]) => {
    if (!entry) {
      return
    }

    const nextCompact = entry.contentRect.width < layoutProfileThresholds.mediumUpperBound
    if (!compact && nextCompact && focusedToggle) {
      requestAnimationFrame(() => {
        shell.querySelector<HTMLElement>('.wl-nav-link[aria-current="page"]')?.focus({
          preventScroll: true,
        })
      })
      focusedToggle = false
    }
    compact = nextCompact
  })

  shell.addEventListener("focusin", recordFocus)
  observer.observe(shell)

  return () => {
    shell.removeEventListener("focusin", recordFocus)
    observer.disconnect()
  }
}

export const preserveShellFocusWithin = (root: ParentNode): (() => void) => {
  let shell: HTMLElement | null = null

  const focusObserver = { stop: () => {} }

  const bindCurrentShell = () => {
    const nextShell = root.querySelector<HTMLElement>(".wotex-lab")
    if (nextShell === shell) {
      return
    }

    focusObserver.stop()
    shell = nextShell
    focusObserver.stop = shell ? preserveShellFocusAcrossProfiles(shell) : () => {}
  }

  const observer = new MutationObserver(bindCurrentShell)
  observer.observe(root, {
    childList: true,
    subtree: true,
  })

  bindCurrentShell()

  return () => {
    observer.disconnect()
    focusObserver.stop()
  }
}
