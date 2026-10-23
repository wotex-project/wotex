const catalogueStatus = (query: string, count: number) => {
  if (!query) {
    return ""
  }
  if (count === 0) {
    return "No matches"
  }
  return `${count} ${count === 1 ? "match" : "matches"}`
}

const requestedCatalogue = (hash: string) => {
  if (hash === "#doc-api") {
    return "api"
  }
  if (hash === "#doc-packages") {
    return "packages"
  }
  return "article"
}

const updateNavigation = (root: HTMLElement, view: string) => {
  const section = view === "article" ? (root.dataset.docSection ?? "guides") : view
  for (const link of root.querySelectorAll<HTMLAnchorElement>(".doc-primary-nav a")) {
    const selected = section === "guides" ? !link.hash : link.hash === `#doc-${section}`
    if (selected) {
      link.setAttribute("aria-current", "page")
    } else {
      link.removeAttribute("aria-current")
    }
  }
}

const filterCatalogue = (catalogue: HTMLElement, query: string) => {
  let count = 0
  for (const item of catalogue.querySelectorAll<HTMLElement>("[data-doc-catalogue-item]")) {
    item.hidden = !(item.textContent ?? "").toLocaleLowerCase().includes(query)
    if (!item.hidden) {
      count++
    }
  }
  for (const group of catalogue.querySelectorAll<HTMLElement>("[data-doc-catalogue-group]")) {
    group.hidden = !group.querySelector("[data-doc-catalogue-item]:not([hidden])")
  }
  const status = catalogue.querySelector<HTMLElement>("[data-doc-catalogue-status]")
  if (status) {
    status.textContent = catalogueStatus(query, count)
  }
}

const mountReader = () => {
  const root = document.querySelector<HTMLElement>(".lab-docs")
  if (!root) {
    return
  }
  const abort = new AbortController()

  const theme = () => {
    const value = document.documentElement.dataset.docTheme ?? root.dataset.docTheme ?? "system"
    root.dataset.wotexTheme = value
    for (const button of root.querySelectorAll<HTMLElement>("[data-doc-theme-value]")) {
      button.setAttribute("aria-pressed", String(button.dataset.docThemeValue === value))
    }
  }

  const observer = new MutationObserver(theme)
  observer.observe(root, {
    attributes: true,
    attributeFilter: ["data-doc-theme"],
  })
  observer.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-doc-theme"],
  })
  theme()

  const catalogueView = () => {
    const requested = requestedCatalogue(location.hash)
    const view =
      requested !== "article" && root.querySelector(`[data-doc-catalogue="${requested}"]`)
        ? requested
        : "article"
    root.dataset.docView = view
    for (const catalogue of root.querySelectorAll<HTMLDetailsElement>("[data-doc-catalogue]")) {
      catalogue.open = catalogue.dataset.docCatalogue === view
      if (catalogue.open) {
        catalogue.querySelector<HTMLElement>("h1")?.focus({
          preventScroll: true,
        })
      }
    }
    updateNavigation(root, view)
  }

  catalogueView()

  window.addEventListener("hashchange", catalogueView, {
    signal: abort.signal,
  })

  root.addEventListener(
    "input",
    (event) => {
      if (
        !(event.target instanceof HTMLInputElement) ||
        !event.target.hasAttribute("data-doc-catalogue-filter")
      ) {
        return
      }
      const catalogue = event.target.closest<HTMLElement>("[data-doc-catalogue]")
      if (!catalogue) {
        return
      }
      const query = event.target.value.trim().toLocaleLowerCase()
      filterCatalogue(catalogue, query)
    },
    {
      signal: abort.signal,
    },
  )

  const copyIcon = root.dataset.docCopyIcon
  if (copyIcon) {
    for (const button of root.querySelectorAll<HTMLButtonElement>("[data-doc-copy]")) {
      const icon = document.createElement("img")
      icon.src = copyIcon
      icon.alt = ""
      button.setAttribute("aria-label", "Copy code")
      button.replaceChildren(icon)
    }
  }

  root.addEventListener(
    "click",
    (event) => {
      if (!(event.target instanceof Element)) {
        return
      }
      const index = event.target.closest<HTMLAnchorElement>("[data-doc-index]")
      if (index) {
        root
          .querySelector<HTMLButtonElement>(
            "[data-doc-search-dialog][open] [data-doc-search-close]",
          )
          ?.click()
        root
          .querySelector<HTMLButtonElement>('[data-doc-nav-toggle][aria-expanded="true"]')
          ?.click()
        if (location.pathname === index.pathname && location.hash === index.hash) {
          catalogueView()
        }
        return
      }
      const scope = event.target.closest<HTMLButtonElement>("[data-doc-search-scope]")
      if (!scope) {
        return
      }
      const select = root.querySelector<HTMLSelectElement>('[data-doc-search-filter="tag"]')
      if (!select) {
        return
      }
      select.value = scope.dataset.docSearchScope ?? ""
      select.dispatchEvent(
        new Event("change", {
          bubbles: true,
        }),
      )
    },
    {
      signal: abort.signal,
    },
  )

  root.addEventListener(
    "change",
    (event) => {
      if (
        !(event.target instanceof HTMLSelectElement) ||
        event.target.dataset.docSearchFilter !== "tag"
      ) {
        return
      }
      const value = event.target.value
      for (const scope of root.querySelectorAll<HTMLButtonElement>("[data-doc-search-scope]")) {
        scope.setAttribute("aria-pressed", String(scope.dataset.docSearchScope === value))
      }
    },
    {
      signal: abort.signal,
    },
  )

  document.addEventListener(
    "keydown",
    (event) => {
      if (event.key !== "Escape") {
        return
      }
      for (const trigger of root.querySelectorAll<HTMLElement>(
        '[data-doc-nav-toggle][aria-expanded="true"]',
      )) {
        trigger.click()
        trigger.focus()
      }
    },
    {
      signal: abort.signal,
    },
  )

  window.addEventListener(
    "pagehide",
    () => {
      abort.abort()
      observer.disconnect()
    },
    {
      once: true,
    },
  )
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", mountReader, {
    once: true,
  })
} else {
  mountReader()
}
