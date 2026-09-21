import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { mkdtemp, readFile, realpath, rm, stat } from "node:fs/promises"
import { createServer } from "node:http"
import { tmpdir } from "node:os"
import { dirname, extname, join, relative, resolve, sep } from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "playwright"

const workbench = dirname(fileURLToPath(new URL("../package.json", import.meta.url)))
const phoenixAssets = await candidate("PHOENIX_ASSETS_CANDIDATE", "../../../../../phoenix-assets")
const docShell = await candidate("DOC_SHELL_CANDIDATE", "../../../../../doc_shell")
const pagefind = join(phoenixAssets, "npm/doc-shell/node_modules/.bin/pagefind")
const livePort = port(process.argv[2] ?? "4104")
const staticPort = port(process.argv[3] ?? "4105")
const started = performance.now()
const temporary = await mkdtemp(join(tmpdir(), "wotex-documentation-browser-"))
const staticRoot = join(temporary, "site")
const liveOrigin = new URL(`http://127.0.0.1:${livePort}`)
const staticOrigin = new URL(`http://127.0.0.1:${staticPort}`)
const child = startFixture()
let staticServer

try {
  const fixture = await fixtureReady(child)
  assert.equal(fixture.static, staticRoot)
  staticServer = await serveStatic(staticRoot, staticPort)

  const browser = await chromium.launch()
  try {
    const live = await checkSurface(browser, liveOrigin, "live")
    const built = await checkSurface(browser, staticOrigin, "static")
    assert.deepEqual(built.content, live.content)
    assert.deepEqual(built.design, live.design)
    await checkNoScript(browser, liveOrigin)
    await checkNoScript(browser, staticOrigin)

    const playwright = JSON.parse(
      await readFile(new URL("../node_modules/playwright/package.json", import.meta.url), "utf8"),
    ).version

    process.stdout.write(
      `${JSON.stringify({
        schema: "wotex-documentation-browser-cohort/v1",
        kind: "local_source_browser_cohort",
        node: process.version,
        playwright,
        chromium: browser.version(),
        cohort_digest: fixture.cohort_digest,
        surfaces: ["live", "static"],
        checks: [
          "shared-page-model",
          "lazy-pagefind",
          "fixed-search-corpus",
          "all-search-filters",
          "keyboard-search-navigation",
          "320px-reflow",
          "400-percent-zoom",
          "themes-high-contrast-reduced-motion",
          "ltr-rtl",
          "javascript-disabled",
          "404-shell",
          "loopback-only-runtime",
        ],
        artifact_adoption: false,
        wcag_certification: false,
        duration_ms: Math.round(performance.now() - started),
        status: "passed",
      })}\n`,
    )
  } finally {
    await browser.close()
  }
} finally {
  if (staticServer) await new Promise((resolveClose) => staticServer.close(resolveClose))
  await stopFixture(child)
  await rm(temporary, { recursive: true, force: true })
}

async function candidate(environment, fallback) {
  const path = resolve(workbench, process.env[environment] ?? fallback)
  return realpath(path)
}

function port(value) {
  const parsed = Number.parseInt(value, 10)
  assert.ok(Number.isInteger(parsed) && parsed >= 1024 && parsed <= 65_535)
  return parsed
}

function startFixture() {
  return spawn(
    "mix",
    [
      "run",
      "--no-start",
      "bin/serve_documentation_browser_fixture.exs",
      "--destination",
      staticRoot,
      "--port",
      String(livePort),
      "--pagefind-executable",
      pagefind,
    ],
    {
      cwd: workbench,
      env: {
        ...process.env,
        MIX_ENV: "test",
        WOTEX_PATH_DEPS: "1",
        PHOENIX_ASSETS_CANDIDATE: phoenixAssets,
        DOC_SHELL_CANDIDATE: docShell,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  )
}

function fixtureReady(process) {
  return new Promise((resolveReady, rejectReady) => {
    let stdout = ""
    let stderr = ""
    const timeout = setTimeout(() => rejectReady(new Error(`fixture timeout\n${stderr}`)), 120_000)

    process.stdout.on("data", (chunk) => {
      stdout += chunk
      const line = stdout
        .split("\n")
        .find((entry) => entry.startsWith("WOTEX_DOCUMENTATION_FIXTURE "))
      if (!line) return
      clearTimeout(timeout)
      resolveReady(JSON.parse(line.slice("WOTEX_DOCUMENTATION_FIXTURE ".length)))
    })
    process.stderr.on("data", (chunk) => {
      stderr = (stderr + chunk).slice(-16_384)
    })
    process.once("exit", (code) => {
      clearTimeout(timeout)
      rejectReady(new Error(`fixture exited with ${code}\n${stdout}\n${stderr}`))
    })
  })
}

async function stopFixture(process) {
  if (process.exitCode !== null) return
  process.kill("SIGTERM")
  await Promise.race([
    new Promise((resolveExit) => process.once("exit", resolveExit)),
    new Promise((resolveTimeout) => setTimeout(resolveTimeout, 5_000)),
  ])
  if (process.exitCode === null) process.kill("SIGKILL")
}

async function serveStatic(root, listenPort) {
  const server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url ?? "/", `http://127.0.0.1:${listenPort}`)
      const decoded = decodeURIComponent(url.pathname)
      const relativePath = decoded.replace(/^\/+/, "")
      let path = resolve(root, relativePath)
      const resolvedRelative = relative(root, path)
      if (resolvedRelative === ".." || resolvedRelative.startsWith(`..${sep}`)) {
        throw new Error("path outside static root")
      }
      if (path === root) path = join(path, "index.html")

      try {
        if ((await stat(path)).isDirectory()) path = join(path, "index.html")
      } catch {
        path = join(root, "404.html")
        response.statusCode = 404
      }

      const bytes = await readFile(path)
      response.setHeader("content-type", mediaType(path))
      response.setHeader("cache-control", "no-store")
      response.end(request.method === "HEAD" ? undefined : bytes)
    } catch {
      response.statusCode = 404
      response.end("not found")
    }
  })

  await new Promise((resolveListen, rejectListen) => {
    server.once("error", rejectListen)
    server.listen(listenPort, "127.0.0.1", resolveListen)
  })
  return server
}

function mediaType(path) {
  if (path.includes("/wasm.") && path.endsWith(".pagefind")) return "application/wasm"
  return (
    {
      ".css": "text/css",
      ".html": "text/html; charset=utf-8",
      ".js": "text/javascript",
      ".json": "application/json",
      ".txt": "text/plain; charset=utf-8",
      ".xml": "application/xml",
    }[extname(path)] ?? "application/octet-stream"
  )
}

async function checkSurface(browser, origin, kind) {
  const context = await browser.newContext({ viewport: { width: 1_280, height: 900 } })
  const page = await context.newPage()
  page.setDefaultTimeout(20_000)
  const errors = []
  const remote = []
  const pagefindRequests = []

  page.on("pageerror", (error) => errors.push(error.message))
  page.on("console", (message) => {
    const location = message.location().url
    const expectedNotFound = location !== "" && new URL(location).pathname === "/docs/not-present/"
    if (message.type() === "error" && !expectedNotFound) errors.push(message.text())
  })
  page.on("request", (request) => {
    const requested = new URL(request.url())
    if (requested.pathname.includes("pagefind")) pagefindRequests.push(requested.pathname)
  })
  await context.route("**/*", async (route) => {
    const requested = new URL(route.request().url())
    if (requested.hostname === "127.0.0.1") await route.continue()
    else {
      remote.push(requested.href)
      await route.abort("blockedbyclient")
    }
  })

  const response = await page.goto(new URL("/docs/start/", origin).href)
  assert.equal(response?.ok(), true, `${kind} start page`)
  assert.equal(pagefindRequests.length, 0, `${kind} search must be lazy`)
  await page.keyboard.press("Control+k")
  assert.equal(
    await page
      .locator("[data-doc-search-input]")
      .evaluate((element) => element === document.activeElement),
    true,
  )

  const queries = [
    ["guide constellation", "Start"],
    ["member orbital decoder", "Wotex.Thing"],
    ["protocol beacon", "Bluetooth beacon"],
    ["specification covenant", "Datagram contract"],
    ["evidence lantern", "Release proof"],
    ["notebook tensor", "Tensor notebook"],
    ["API operation widget flight", "Widget API"],
  ]
  for (const [query, title] of queries) await search(page, query, title)
  assert.ok(pagefindRequests.some((path) => path.endsWith("/pagefind.js")))
  assert.ok(pagefindRequests.some((path) => path.includes(".pf_")))

  const filters = {
    collection: "family_docs",
    kind: "guide",
    locale: "en",
    audience: "public",
    version: "0.1.0",
    tag: "start",
    status: "stable",
  }
  for (const [name, value] of Object.entries(filters)) {
    await clearFilters(page)
    await page.locator(`[data-doc-search-filter='${name}']`).selectOption(value)
    await search(page, "guide constellation", "Start")
  }

  await page.locator("[data-doc-search-close]").click()
  await page.setViewportSize({ width: 320, height: 900 })
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true)
  await page.getByRole("button", { name: "Browse documentation" }).click()
  assert.equal(await page.locator("[data-doc-nav]").getAttribute("data-doc-nav-state"), "open")

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
      ratio: devicePixelRatio,
      width: innerWidth,
      reflows: document.documentElement.scrollWidth <= innerWidth,
    })),
    { ratio: 4, width: 320, reflows: true },
  )
  await session.send("Emulation.clearDeviceMetricsOverride")

  for (const theme of ["Light", "Dark", "High contrast", "System"]) {
    await page.getByRole("button", { name: theme }).click()
  }
  await page.emulateMedia({ reducedMotion: "reduce", forcedColors: "active" })
  const durations = await page.locator(".doc-shell *").evaluateAll((elements) =>
    elements.flatMap((element) => {
      const style = getComputedStyle(element)
      return [style.animationDuration, style.transitionDuration]
        .flatMap((value) => value.split(","))
        .map((value) => value.trim())
    }),
  )
  assert.ok(durations.every((value) => durationMilliseconds(value) <= 0.01))

  const rtlResponse = await page.goto(new URL("/docs/start/rtl-guide/", origin).href)
  assert.equal(rtlResponse?.ok(), true)
  assert.equal(await page.locator(".doc-shell").getAttribute("dir"), "rtl")
  assert.equal(await page.locator(".doc-shell").getAttribute("lang"), "ar")

  const missing = await page.goto(new URL("/docs/not-present/", origin).href)
  assert.equal(missing?.status(), kind === "static" ? 404 : 200)
  await page.getByRole("heading", { name: "Page not found" }).waitFor()
  assert.equal(await page.getByRole("navigation", { name: "Documentation" }).count(), 1)
  assert.equal(await page.getByRole("button", { name: "Search documentation" }).count(), 1)

  await page.goto(new URL("/docs/start/", origin).href)
  const content = await page.evaluate(() => ({
    title: document.querySelector("h1")?.textContent?.trim(),
    article: document.querySelector("article")?.textContent?.replace(/\s+/g, " ").trim(),
    headings: [...document.querySelectorAll("article h1, article h2, article h3")].map((item) =>
      item.textContent?.trim(),
    ),
    navigation: [...document.querySelectorAll("nav[aria-label='Documentation'] a")].map((link) => [
      link.textContent?.trim(),
      link.getAttribute("href"),
    ]),
    searchName: document.querySelector("[data-doc-search-open]")?.textContent?.trim(),
  }))
  const design = await page.locator(".doc-shell").evaluate((element) => ({
    cohort: element.getAttribute("data-cohort-digest"),
    tokens: element.getAttribute("data-pa-token-digest"),
    components: element.getAttribute("data-pa-component-digest"),
    fixtures: element.getAttribute("data-pa-fixture-digest"),
    css: element.getAttribute("data-pa-css-digest"),
  }))

  assert.deepEqual(errors, [])
  assert.deepEqual(remote, [])
  await context.close()
  return { content, design }
}

async function search(page, query, expectedTitle) {
  const input = page.locator("[data-doc-search-input]")
  await input.fill(query)
  await page.waitForFunction((title) => {
    const list = document.querySelector("[data-doc-search-results]")
    return (
      list?.getAttribute("data-doc-search-state") === "ready" && list.textContent?.includes(title)
    )
  }, expectedTitle)
}

async function clearFilters(page) {
  for (const filter of await page.locator("[data-doc-search-filter]").all()) {
    await filter.selectOption("")
  }
}

function durationMilliseconds(value) {
  const amount = Number.parseFloat(value)
  if (!Number.isFinite(amount)) return 0
  return value.endsWith("ms") ? amount : amount * 1_000
}

async function checkNoScript(browser, origin) {
  const context = await browser.newContext({ javaScriptEnabled: false })
  const page = await context.newPage()
  await page.goto(new URL("/docs/start/", origin).href)
  assert.equal(await page.locator("article").count(), 1)
  assert.equal(await page.getByRole("navigation", { name: "Documentation" }).count(), 1)
  assert.equal((await page.locator("noscript a").count()) > 0, true)
  await context.close()
}
