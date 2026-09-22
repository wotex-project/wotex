import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { chromium } from "playwright"

const workbenchOrigin = localOrigin(process.argv[2] ?? "http://127.0.0.1:4000")
const storybookOrigin = localOrigin(process.argv[3] ?? "http://127.0.0.1:4103")
const playwrightVersion = JSON.parse(
  await readFile(new URL("../node_modules/playwright/package.json", import.meta.url), "utf8"),
).version

function localOrigin(value) {
  const origin = new URL(value)
  assert.equal(origin.protocol, "http:")
  assert.equal(origin.hostname, "127.0.0.1", "browser cohorts require a loopback host")
  origin.pathname = "/"
  origin.search = ""
  origin.hash = ""
  return origin
}

const url = (origin, path) => new URL(path, origin).href

const watchErrors = (page) => {
  const errors = []
  page.on("pageerror", (error) => errors.push(error.message))
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text())
  })
  page.on("dialog", async (dialog) => {
    errors.push(`dialog: ${dialog.message()}`)
    await dialog.dismiss()
  })
  return errors
}

const waitForLiveView = (page) =>
  page.waitForFunction(
    () => window.liveSocket?.isConnected() && document.querySelector("[data-phx-main].phx-connected"),
  )

const waitForIslandState = (page, state, count) =>
  page.waitForFunction(
    ({ expectedState, expectedCount }) => {
      const islands = [...document.querySelectorAll("[data-wotex-island]")]
      return (
        islands.length === expectedCount &&
        islands.every((island) => island.getAttribute("data-wotex-island-state") === expectedState)
      )
    },
    { expectedState: state, expectedCount: count },
  )

const assertFallbackHandoff = async (page, visible) => {
  const states = await page.locator("[data-wotex-island]").evaluateAll((islands) =>
    islands.map((island) => {
      const fallback = island.querySelector("[data-wotex-island-fallback]")
      const mount = island.querySelector("[data-wotex-island-mount]")
      return {
        fallback: fallback ? getComputedStyle(fallback).display : "missing",
        mount: mount ? getComputedStyle(mount).display : "missing",
      }
    }),
  )

  assert.ok(states.length > 0)
  for (const state of states) {
    assert.equal(state.fallback !== "none", visible)
    assert.equal(state.mount === "none", visible)
  }
}

const assertUniqueInstances = async (page) => {
  const identities = await page
    .locator("[data-wotex-island-mount]")
    .evaluateAll((mounts) => mounts.map((mount) => mount.getAttribute("data-wotex-island-instance")))
  assert.equal(new Set(identities).size, identities.length)
  assert.ok(identities.every((identity) => typeof identity === "string" && identity.length > 0))
  return identities
}

const assertReflow = async (page, width) => {
  await page.setViewportSize({ width, height: 900 })
  assert.equal(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    true,
  )
}

const assertFourHundredPercentZoom = async (context, page) => {
  const session = await context.newCDPSession(page)
  await session.send("Emulation.setDeviceMetricsOverride", {
    width: 320,
    height: 225,
    screenWidth: 1_280,
    screenHeight: 900,
    deviceScaleFactor: 4,
    mobile: false,
  })
  assert.deepEqual(
    await page.evaluate(() => ({
      pixelRatio: window.devicePixelRatio,
      viewport: window.innerWidth,
      reflows: document.documentElement.scrollWidth <= window.innerWidth,
    })),
    { pixelRatio: 4, viewport: 320, reflows: true },
  )
  await session.send("Emulation.clearDeviceMetricsOverride")
}

const assertThemesAndMotion = async (page) => {
  for (const theme of ["light", "dark", "system"]) {
    const selector = page.locator("#wl-theme")
    if ((await selector.count()) === 1) await selector.selectOption(theme)
    assert.ok((await page.locator("[data-wotex-island]").count()) > 0)
  }

  const island = page.locator("[data-wotex-island]").first()
  const normal = await island.evaluate((element) => {
    element.setAttribute("data-wotex-theme", "light")
    const style = getComputedStyle(element)
    return [style.backgroundColor, style.color]
  })
  const contrast = await island.evaluate((element) => {
    element.setAttribute("data-wotex-theme", "contrast")
    const style = getComputedStyle(element)
    return [style.backgroundColor, style.color]
  })
  assert.notDeepEqual(contrast, normal)

  await page.emulateMedia({ reducedMotion: "reduce" })
  const durations = await page.locator("[data-wotex-island] *").evaluateAll((elements) =>
    elements.flatMap((element) => {
      const style = getComputedStyle(element)
      return [style.animationDuration, style.transitionDuration]
        .flatMap((value) => value.split(","))
        .map((value) => value.trim())
    }),
  )
  const milliseconds = durations.map((value) =>
    value.endsWith("ms") ? Number.parseFloat(value) : Number.parseFloat(value) * 1_000,
  )
  assert.ok(milliseconds.every((value) => !Number.isFinite(value) || value <= 0.01))
}

const checkWorkbench = async (browser) => {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
  const page = await context.newPage()
  const errors = watchErrors(page)
  page.setDefaultTimeout(15_000)

  const response = await page.goto(workbenchOrigin.href)
  assert.equal(response?.ok(), true)
  assert.ok(!response?.headers()["content-security-policy"]?.includes("unsafe-eval"))
  await waitForLiveView(page)
  await waitForIslandState(page, "mounted", 1)
  await assertFallbackHandoff(page, false)
  const [overviewIdentity] = await assertUniqueInstances(page)

  const tabs = page.locator("[data-wotex-island='tabs'] [role='tab']")
  assert.ok((await tabs.count()) >= 2)
  await tabs.first().focus()
  await page.keyboard.press("ArrowRight")
  assert.equal(await tabs.nth(1).getAttribute("aria-selected"), "true")
  assert.equal(await tabs.nth(1).evaluate((element) => element.matches(":focus-visible")), true)
  await assertThemesAndMotion(page)
  await assertReflow(page, 320)
  await assertFourHundredPercentZoom(context, page)

  await page.setViewportSize({ width: 1280, height: 900 })
  await page.locator("button[phx-click='start_room']").click()
  await page.locator("#run-thermal button[type='submit']").click()
  await page.waitForURL("**/runs/**")
  await waitForIslandState(page, "mounted", 1)
  assert.equal(await page.locator("[data-wotex-island='chart'] .wl-island-table").count(), 1)
  assert.equal(await page.locator("[data-wotex-island='chart'] [data-wotex-island-mount] figcaption").count(), 1)
  assert.ok((await page.locator("[data-wotex-island-fallback] tbody tr").count()) <= 100)

  const runsBeforeReconnect = await page.evaluate(async () => {
    const result = await fetch("/evidence/report.json")
    return (await result.json()).runs
  })
  await page.evaluate(() => window.liveSocket.disconnect())
  await waitForIslandState(page, "disconnected", 1)
  await assertFallbackHandoff(page, true)
  await page.evaluate(() => window.liveSocket.connect())
  await waitForLiveView(page)
  await waitForIslandState(page, "mounted", 1)
  await assertFallbackHandoff(page, false)
  const runsAfterReconnect = await page.evaluate(async () => {
    const result = await fetch("/evidence/report.json")
    return (await result.json()).runs
  })
  assert.deepEqual(runsAfterReconnect, runsBeforeReconnect)

  await page.goto(url(workbenchOrigin, "/metrics"))
  await waitForLiveView(page)
  await page.locator("#metric-query button[type='submit']").click()
  await waitForIslandState(page, "mounted", 1)
  const firstCell = page.locator("[data-wotex-island='data-grid'] [role='gridcell']").first()
  await firstCell.focus()
  await page.keyboard.press("ArrowRight")
  assert.equal(
    await page.locator("[data-wotex-island='data-grid'] [role='gridcell']:focus").count(),
    1,
  )
  await page.keyboard.press("Enter")

  for (let iteration = 0; iteration < 3; iteration += 1) {
    await page.goto(url(workbenchOrigin, "/things"))
    await waitForLiveView(page)
    assert.equal(await page.locator("[data-wotex-island]").count(), 0)
    await page.goto(workbenchOrigin.href)
    await waitForLiveView(page)
    await waitForIslandState(page, "mounted", 1)
    assert.deepEqual(await assertUniqueInstances(page), [overviewIdentity])
  }

  const isolated = await browser.newContext()
  const isolatedPage = await isolated.newPage()
  await isolatedPage.goto(workbenchOrigin.href)
  await waitForLiveView(isolatedPage)
  await waitForIslandState(isolatedPage, "mounted", 1)
  const isolatedIdentities = await assertUniqueInstances(isolatedPage)
  assert.ok(!isolatedIdentities.includes(overviewIdentity))
  await isolated.close()

  assert.deepEqual(errors, [])
  await context.close()
}

const checkWorkbenchFallbacks = async (browser) => {
  const noScript = await browser.newContext({ javaScriptEnabled: false })
  const noScriptPage = await noScript.newPage()
  await noScriptPage.goto(workbenchOrigin.href)
  assert.equal(await noScriptPage.locator("main#main").count(), 1)
  assert.equal(await noScriptPage.locator("nav[aria-label='Workbench']").count(), 1)
  assert.equal(await noScriptPage.locator("[data-wotex-island-fallback]").isVisible(), true)
  assert.equal(await noScriptPage.locator("[data-wotex-island-mount] > *").count(), 0)
  await noScriptPage.getByRole("link", { name: "Things" }).click()
  assert.equal(new URL(noScriptPage.url()).pathname, "/things")
  await noScript.close()

  const blocked = await browser.newContext()
  const blockedPage = await blocked.newPage()
  await blockedPage.route(/\/assets\/island-(?:tabs|chart|data-grid)-island-[^/]+\.js$/, (route) =>
    route.abort("blockedbyclient"),
  )
  await blockedPage.goto(workbenchOrigin.href)
  await waitForLiveView(blockedPage)
  await waitForIslandState(blockedPage, "failed", 1)
  await assertFallbackHandoff(blockedPage, true)
  await blockedPage.locator("button[phx-click='start_room']").click()
  assert.equal(await blockedPage.locator("#run-thermal button[type='submit']").isEnabled(), true)
  await blocked.close()

  const invalid = await browser.newContext()
  const invalidPage = await invalid.newPage()
  await invalidPage.route(/\/assets\/workbench-[^/]+\.js$/, async (route) => {
    const response = await route.fetch()
    await new Promise((resolve) => setTimeout(resolve, 50))
    await route.fulfill({ response })
  })
  await invalidPage.addInitScript(() => {
    const setAttribute = Element.prototype.setAttribute
    Element.prototype.setAttribute = function (name, value) {
      return setAttribute.call(
        this,
        name,
        name === "data-wotex-island-snapshot" ? "not-a-snapshot" : value,
      )
    }
    new MutationObserver(() => {
      const mount = document.querySelector("[data-wotex-island-snapshot]")
      if (mount) mount.setAttribute("data-wotex-island-snapshot", "not-a-snapshot")
    }).observe(document, { childList: true, subtree: true })
  })
  await invalidPage.goto(workbenchOrigin.href)
  await waitForLiveView(invalidPage)
  await waitForIslandState(invalidPage, "failed", 1)
  await assertFallbackHandoff(invalidPage, true)
  await invalidPage.locator("button[phx-click='start_room']").click()
  assert.equal(await invalidPage.locator("#run-thermal button[type='submit']").isEnabled(), true)
  await invalid.close()
}

const checkStorybook = async (browser) => {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
  const page = await context.newPage()
  const errors = watchErrors(page)
  page.setDefaultTimeout(15_000)
  const response = await page.goto(url(storybookOrigin, "/storybook/islands"))
  assert.equal(response?.ok(), true)
  assert.ok(!response?.headers()["content-security-policy"]?.includes("unsafe-eval"))
  await waitForLiveView(page)
  await waitForIslandState(page, "mounted", 3)
  await assertFallbackHandoff(page, false)
  await assertUniqueInstances(page)

  const chart = page.locator("[data-fixture-id='reporting-chart']")
  await chart.locator(".wl-island-chart-inspect").first().click()
  assert.equal(await chart.locator(".wl-island-table").count(), 1)

  const grid = page.locator("[data-fixture-id='data-grid']")
  const cell = grid.locator("[role='gridcell']").first()
  await cell.focus()
  await page.keyboard.press("ArrowRight")
  assert.equal(await grid.locator("[role='gridcell']:focus").count(), 1)
  await page.keyboard.press("Enter")
  await grid.locator("[role='gridcell']").first().dblclick()

  const tabs = page.locator("[data-fixture-id='navigation-tabs']")
  const firstTab = tabs.locator("[role='tab']").first()
  await firstTab.focus()
  await page.keyboard.press("ArrowRight")
  const focusedTab = tabs.locator("[role='tab']:focus")
  const focusedTabId = await focusedTab.getAttribute("id")
  await tabs.locator("button", { hasText: "Advance server revision" }).evaluate((button) =>
    button.click(),
  )
  await page.waitForFunction(
    () =>
      document.querySelector("[data-fixture-id='navigation-tabs']")?.getAttribute(
        "data-server-revision",
      ) === "2",
  )
  assert.equal(await tabs.locator("[role='tab']:focus").getAttribute("id"), focusedTabId)

  await assertThemesAndMotion(page)
  await assertReflow(page, 320)
  await assertFourHundredPercentZoom(context, page)
  await page.evaluate(() => window.liveSocket.disconnect())
  await waitForIslandState(page, "disconnected", 3)
  await assertFallbackHandoff(page, true)
  await page.evaluate(() => window.liveSocket.connect())
  await waitForLiveView(page)
  await waitForIslandState(page, "mounted", 3)
  await assertFallbackHandoff(page, false)

  assert.deepEqual(errors, [])
  await context.close()

  const blocked = await browser.newContext()
  const blockedPage = await blocked.newPage()
  await blockedPage.route(/\/assets\/island-(?:tabs|chart|data-grid)-island-[^/]+\.js$/, (route) =>
    route.abort("blockedbyclient"),
  )
  await blockedPage.goto(url(storybookOrigin, "/storybook/islands"))
  await waitForLiveView(blockedPage)
  await waitForIslandState(blockedPage, "failed", 3)
  await assertFallbackHandoff(blockedPage, true)
  await blockedPage
    .locator("[data-fixture-id='navigation-tabs'] button", {
      hasText: "Advance server revision",
    })
    .click()
  await blockedPage.waitForFunction(
    () =>
      document.querySelector("[data-fixture-id='navigation-tabs']")?.getAttribute(
        "data-server-revision",
      ) === "2",
  )
  assert.equal(
    await blockedPage
      .locator("[data-fixture-id='navigation-tabs']")
      .getAttribute("data-server-revision"),
    "2",
  )
  await blocked.close()
}

const browser = await chromium.launch({ headless: true })
try {
  await checkWorkbench(browser)
  await checkWorkbenchFallbacks(browser)
  await checkStorybook(browser)
  process.stdout.write(
    `${JSON.stringify({
      schema: "wotex-lab-browser-cohort/v1",
      kind: "local_source_browser_cohort",
      node: process.version,
      playwright: playwrightVersion,
      chromium: browser.version(),
      checks: [
        "real-island-mount-update-destroy",
        "keyboard-and-pointer",
        "focus-recovery",
        "320px-reflow",
        "400-percent-zoom",
        "themes-and-high-contrast",
        "reduced-motion",
        "javascript-disabled-fallback",
        "blocked-chunk-fallback",
        "invalid-snapshot-fallback",
        "disconnect-full-resync",
        "no-reconnect-replay",
        "session-isolation",
        "assistive-content-handoff",
        "safe-server-actions-without-islands",
      ],
      status: "passed",
      artifact_adoption: false,
      wcag_certification: false,
    })}\n`,
  )
} finally {
  await browser.close()
}
