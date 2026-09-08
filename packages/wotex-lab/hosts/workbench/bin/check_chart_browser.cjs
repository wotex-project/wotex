// Explicit local browser cohort. Supply Playwright through the operator's
// tool environment; no browser or dependency is downloaded by this script.
const assert = require("node:assert/strict");
const {chromium} = require("playwright");
const version = require("playwright/package.json").version;

async function run() {
  const origin = new URL(process.argv[2] || "http://127.0.0.1:4000");
  assert.equal(origin.protocol, "http:");
  assert.equal(origin.hostname, "127.0.0.1", "only an explicitly local disposable host is admitted");
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage({viewport: {width: 1280, height: 900}});
    page.setDefaultTimeout(15_000);
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
    const response = await page.goto(origin.href);
    assert.ok(!response.headers()["content-security-policy"].includes("unsafe-eval"));
    await page.locator("button[phx-click=start_room]").click();
    await page.locator("#run-thermal button[type=submit]").click();
    await page.waitForURL("**/runs/**");
    const runPath = new URL(page.url()).pathname;
    const chart = page.locator(".wl-chart-enhanced svg");
    await chart.waitFor({state: "visible"});
    assert.equal(await chart.count(), 1);
    assert.equal(await page.locator(".wl-chart-svg").isVisible(), false);

    for (const theme of ["dark", "light", "system"]) {
      await page.locator("#wl-theme").selectOption(theme);
      await chart.waitFor({state: "visible"});
      await page.locator("[data-chart-reset]").focus();
      await page.keyboard.press("Enter");
      await chart.waitFor({state: "visible"});
      assert.equal(await chart.count(), 1);
    }

    await page.setViewportSize({width: 375, height: 812});
    await page.emulateMedia({reducedMotion: "reduce"});
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await page.locator(".wl-chart-table summary").click();
    assert.ok(await page.locator(".wl-chart-table tbody tr").count() <= 100);

    await page.reload();
    await chart.waitFor({state: "visible"});
    assert.equal(new URL(page.url()).pathname, runPath);
    assert.equal(await page.locator("form[phx-submit=approve]").count(), 0);
    const other = await browser.newPage();
    await other.goto(new URL(runPath, origin).href);
    assert.ok(await other.getByText("Run unavailable", {exact: true}).isVisible());
    await other.close();
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({
      kind: "local_source_browser_cohort", node: process.version, playwright: version,
      chromium: browser.version(), checks: ["CSP-interpreter", "enhanced-render", "theme-reset",
        "keyboard-reset", "mobile-reflow", "bounded-table", "reload-no-replay", "session-isolation"],
      status: "passed", artifact_adoption: false, wcag_certification: false
    }));
  } finally { await browser.close(); }
}

run().catch((error) => { console.error(error); process.exitCode = 1; });
