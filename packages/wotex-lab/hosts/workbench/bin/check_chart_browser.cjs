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
    assert.equal(await page.locator("main#main").count(), 1);
    assert.equal(await page.locator("nav[aria-label=Workbench]").count(), 1);
    await page.locator(".wl-skip").focus();
    assert.ok(await page.locator(".wl-skip").isVisible());
    await page.locator("button[phx-click=start_room]").click();
    await page.locator("#run-thermal button[type=submit]").click();
    await page.waitForURL("**/runs/**");
    const runPath = new URL(page.url()).pathname;
    const chart = page.locator(".wl-chart-svg");
    await chart.waitFor({state: "visible"});
    assert.equal(await chart.count(), 1);

    const beforeRuns = await page.evaluate(async () => (await (await fetch("/evidence/report.json")).json()).runs);
    assert.equal(await page.locator("#run-insights").count(), 0);
    for (const mark of ["point", "area", "line"]) {
      await page.locator("#analysis-mark").selectOption(mark);
      await page.locator("#run-analysis button[type=submit]").click();
      await page.locator("#run-insights").waitFor({state: "visible"});
      await page.waitForFunction(({selector, alternatives}) => {
        const series = document.querySelector(".wl-chart-svg .wl-chart-series");
        return series && series.querySelector(selector) &&
          alternatives.every((alternative) => !series.querySelector(alternative));
      }, {
        selector: {point: "circle", area: "polygon", line: "polyline"}[mark],
        alternatives: {
          point: ["polygon", "polyline"],
          area: ["circle", "polyline"],
          line: ["circle", "polygon"]
        }[mark]
      });
      await chart.waitFor({state: "visible"});
      assert.equal(await chart.count(), 1);
    }
    const analysisHref = await page.locator("#analysis-deep-link").getAttribute("href");
    assert.ok(analysisHref.includes("analysis[mark]=line"));
    const chartHref = await page.locator(".wl-chart-link").getAttribute("href");
    assert.ok(chartHref.endsWith("#run-chart-0"));
    await page.goto(new URL(chartHref, origin).href);
    await page.locator("#run-insights").waitFor({state: "visible"});
    assert.equal(new URL(page.url()).hash, "#run-chart-0");
    assert.ok(await page.locator("#analysis-preview tbody tr").count() <= 100);
    const afterRuns = await page.evaluate(async () => (await (await fetch("/evidence/report.json")).json()).runs);
    assert.deepEqual(afterRuns, beforeRuns);

    for (const theme of ["dark", "light", "system"]) {
      await page.locator("#wl-theme").selectOption(theme);
      await chart.waitFor({state: "visible"});
      assert.equal(await chart.count(), 1);
    }

    await page.setViewportSize({width: 375, height: 812});
    await page.emulateMedia({reducedMotion: "reduce"});
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await page.locator(".wl-chart-table summary").click();
    assert.ok(await page.locator(".wl-chart-table tbody tr").count() <= 100);

    await page.goto(new URL(runPath, origin).href);
    await page.reload();
    await chart.waitFor({state: "visible"});
    assert.equal(await page.locator("#run-insights").count(), 0);
    assert.equal(new URL(page.url()).pathname, runPath);
    assert.equal(await page.locator("form[phx-submit=approve]").count(), 0);
    const other = await browser.newPage();
    await other.goto(new URL(runPath, origin).href);
    assert.ok(await other.getByText("Run unavailable", {exact: true}).isVisible());
    await other.close();

    await page.goto(new URL("/metrics", origin).href);
    await page.locator("#metric-catalogue summary").focus();
    await page.keyboard.press("Enter");
    const choices = page.locator("#dashboard-selection input[type=checkbox]");
    assert.equal(await choices.count(), 43);
    for (const choice of await choices.all()) await choice.uncheck();
    await page.locator("#dashboard-selection input[value=nx_duration_seconds]").check();
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await page.locator("#dashboard-selection button[type=submit]").click();
    await page.getByText("Dashboard arrangement saved for this session.", {exact: true}).waitFor();
    await page.goto(new URL("/metrics", origin).href);
    await page.locator("#metric-catalogue summary").click();
    assert.ok(await page.locator("#dashboard-selection input[value=nx_duration_seconds]").isChecked());
    assert.equal(await page.locator("#dashboard-selection input:checked").count(), 1);
    const dashboardHref = await page.locator("#dashboard-deep-link").getAttribute("href");
    assert.ok(dashboardHref.includes("nx_duration_seconds"));
    const [download] = await Promise.all([
      page.waitForEvent("download"),
      page.locator("#dashboard-export").click()
    ]);
    assert.equal(download.suggestedFilename(), "wotex-lab-dashboard.json");
    const chunks = [];
    let size = 0;
    for await (const chunk of await download.createReadStream()) {
      size += chunk.length;
      assert.ok(size <= 65_536);
      chunks.push(chunk);
    }
    const dashboard = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    assert.equal(dashboard.panels.length, 1);
    assert.equal(dashboard.panels[0].targets[0].expr,
      "histogram_quantile(0.95, rate(wotex_lab_nx_duration_seconds_bucket[5m]))");
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({
      kind: "local_source_browser_cohort", node: process.version, playwright: version,
      chromium: browser.version(), checks: ["CSP", "native-svg", "theme",
        "mobile-reflow", "bounded-table", "server-mark-updates",
        "analysis-deep-link", "chart-fragment", "analysis-no-evidence-mutation",
        "reload-no-replay", "session-isolation", "keyboard-skip-and-details",
        "catalogue-selection", "saved-dashboard", "catalogue-mobile-reflow",
        "dashboard-deep-link", "dashboard-download"],
      status: "passed", artifact_adoption: false, wcag_certification: false
    }));
  } finally { await browser.close(); }
}

run().catch((error) => { console.error(error); process.exitCode = 1; });
