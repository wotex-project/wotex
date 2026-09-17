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
    page.on("dialog", async (dialog) => { errors.push(`dialog: ${dialog.message()}`); await dialog.dismiss(); });
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

    const connected = () => page.waitForFunction(() => window.liveSocket.isConnected() &&
      document.querySelector("[data-phx-main].phx-connected") !== null);
    const reconnect = async () => {
      await page.evaluate(() => window.liveSocket.disconnect());
      await page.waitForFunction(() => !window.liveSocket.isConnected());
      await page.evaluate(() => window.liveSocket.connect());
      await connected();
    };
    const reportRun = (id) => page.evaluate(async (runId) =>
      (await (await fetch("/evidence/report.json")).json()).runs.find((run) => run.id === runId), id);
    const startSmartRoom = async () => {
      await page.goto(origin.href);
      await connected();
      await page.locator("#run-smart_room button[type=submit]").click();
      await page.waitForURL("**/runs/**");
      await connected();
      return new URL(page.url()).pathname.split("/").pop();
    };
    const approval = page.locator("form[phx-submit=approve]");

    const approvedId = await startSmartRoom();
    await approval.waitFor({state: "visible"});
    assert.ok(await page.getByText("Running the experiment did not dispatch it.").isVisible());
    assert.ok(await page.locator("#investigation-prompt").isDisabled());
    assert.ok(await page.locator("#investigation button[type=submit]").isDisabled());
    assert.ok(await page.getByText("No investigation provider is configured.", {exact: true}).isVisible());
    assert.equal(await page.locator("#investigation-disclosure").count(), 0);
    await reconnect();
    assert.equal(await approval.count(), 1);
    const pending = await reportRun(approvedId);
    assert.equal(pending.status, "awaiting_approval");
    assert.equal(pending.dispatch, null);
    await approval.locator("button[type=submit]").focus();
    await page.keyboard.press("Enter");
    await approval.waitFor({state: "detached"});
    const dispatched = await reportRun(approvedId);
    assert.equal(dispatched.status, "dispatched");
    assert.ok(dispatched.dispatch);
    await reconnect();
    await page.reload();
    await connected();
    assert.equal(await approval.count(), 0);
    assert.deepEqual(await reportRun(approvedId), dispatched);

    const cancelledId = await startSmartRoom();
    await approval.waitFor({state: "visible"});
    await page.locator("button[phx-click=cancel]").click();
    await approval.waitFor({state: "detached"});
    await reconnect();
    assert.equal(await approval.count(), 0);
    const cancelled = await reportRun(cancelledId);
    assert.equal(cancelled.status, "cancelled");
    assert.equal(cancelled.dispatch, null);
    assert.deepEqual(await reportRun(approvedId), dispatched);

    await page.goto(new URL("/things", origin).href);
    await connected();
    const hostileTitle = "<img src=x onerror=\"window.__wotexHostile=1\"><script>window.__wotexHostile=2</script>";
    await page.locator("#thing-description").fill(JSON.stringify({
      "@context": "https://www.w3.org/2022/wot/td/v1.1", id: "urn:test:hostile", title: hostileTitle,
      security: ["nosec_sc"], securityDefinitions: {nosec_sc: {scheme: "nosec"}}
    }));
    await page.locator("#register-td button[type=submit]").click();
    await page.getByText(hostileTitle, {exact: true}).first().waitFor({state: "visible"});
    assert.equal(await page.locator("main img, main script").count(), 0);
    assert.equal(await page.evaluate(() => window.__wotexHostile), undefined);

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

    assert.equal(await page.locator("#history-results").count(), 0);
    await page.locator("#history-range").selectOption("5m");
    await page.locator("#history-query button[type=submit]").focus();
    await page.keyboard.press("Enter");
    const historyChart = page.locator("#history-chart-nx_duration_seconds svg.wl-chart-svg");
    await historyChart.waitFor({state: "visible"});
    assert.equal(await page.locator("#history-results").getAttribute("aria-live"), "polite");
    assert.ok(await page.getByText(/p95 per step in seconds; 3 of 3 label sets/).isVisible());
    assert.equal(await page.locator("#history-chart-nx_duration_seconds .wl-chart-series").count(), 3);
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await page.reload();
    await page.locator("#history-query").waitFor({state: "visible"});
    assert.equal(await page.locator("#history-results").count(), 0);
    const historyOther = await browser.newPage();
    await historyOther.goto(new URL("/metrics", origin).href);
    await historyOther.locator("#metric-catalogue").waitFor({state: "visible"});
    assert.equal(await historyOther.locator("#history-query").count(), 0);
    await historyOther.close();

    const freshContext = await browser.newContext({viewport: {width: 1280, height: 900}});
    const fresh = await freshContext.newPage();
    fresh.setDefaultTimeout(15_000);
    fresh.on("pageerror", (error) => errors.push(error.message));
    let probingNoRoom = false;
    fresh.on("console", (message) => {
      const expected = probingNoRoom && message.text().includes("status of 404");
      if (message.type() === "error" && !expected) errors.push(message.text());
    });
    const freshConnected = () => fresh.waitForFunction(() => window.liveSocket.isConnected() &&
      document.querySelector("[data-phx-main].phx-connected") !== null);
    const freshReport = () => fresh.evaluate(async () => (await fetch("/evidence/report.json")).json());
    for (const [path, title] of [["/things", "No room"], ["/metrics", "No room"], ["/evidence", "No evidence yet"]]) {
      await fresh.goto(new URL(path, origin).href);
      await freshConnected();
      assert.ok(await fresh.locator(`section.wl-empty[aria-label="${title}"]`).isVisible());
      assert.equal(await fresh.locator("#metric-query, #register-td, #formal-verify").count(), 0);
    }
    probingNoRoom = true;
    const noRoom = await fresh.evaluate(async () => {
      const response = await fetch("/evidence/report.json");
      return {status: response.status, text: await response.text()};
    });
    probingNoRoom = false;
    assert.equal(noRoom.status, 404);
    assert.ok(noRoom.text.startsWith("no room"));

    await fresh.goto(new URL("/metrics", origin).href);
    await freshConnected();
    await fresh.locator("button[phx-click=start_room]").focus();
    await fresh.keyboard.press("Enter");
    await fresh.locator("#metric-query").waitFor({state: "visible"});
    assert.ok(await fresh.locator('section.wl-empty[aria-label="No session measurements"]').isVisible());
    assert.deepEqual((await freshReport()).runs, []);

    const runThermal = async () => {
      await fresh.goto(origin.href);
      await freshConnected();
      await fresh.locator("#run-thermal button[type=submit]").click();
      await fresh.waitForURL("**/runs/**");
      await fresh.goto(new URL("/metrics", origin).href);
      await freshConnected();
      await fresh.locator("#metric-query button[type=submit]").click();
      const retained = fresh.locator('section[aria-label="Retained samples"] .wl-metric-value span');
      await retained.waitFor({state: "visible"});
      return Number(await retained.textContent());
    };
    const firstSamples = await runThermal();
    assert.ok(firstSamples > 0);
    await fresh.locator("button[phx-click=export_dataset]").click();
    await fresh.waitForFunction(async () =>
      (await (await fetch("/evidence/report.json")).json()).datasets.length === 1);
    const frozen = (await freshReport()).datasets;
    const laterSamples = await runThermal();
    assert.ok(laterSamples > firstSamples);
    const after = await freshReport();
    assert.equal(after.runs.length, 2);
    assert.deepEqual(after.datasets, frozen);

    await fresh.goto(new URL("/evidence", origin).href);
    await freshConnected();
    await fresh.locator("#formal-verify button[type=submit]").click();
    await fresh.getByText("no verified Maude engine is configured").first().waitFor({state: "visible"});
    assert.deepEqual((await freshReport()).datasets, frozen);
    await freshContext.close();
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({
      kind: "local_source_browser_cohort", node: process.version, playwright: version,
      chromium: browser.version(), checks: ["CSP", "native-svg", "theme",
        "mobile-reflow", "bounded-table", "server-mark-updates",
        "analysis-deep-link", "chart-fragment", "analysis-no-evidence-mutation",
        "reload-no-replay", "session-isolation", "keyboard-skip-and-details",
        "catalogue-selection", "saved-dashboard", "catalogue-mobile-reflow",
        "dashboard-deep-link", "dashboard-download", "history-panels", "history-keyboard-submit",
        "history-mobile-reflow", "history-reload-no-replay", "history-session-isolation",
        "approval-keyboard-submit", "approval-reconnect-no-replay", "cancel-reconnect-no-dispatch",
        "hostile-td-escaped", "no-llm-composer-disabled", "fresh-session-empty-states",
        "keyboard-room-start", "frozen-dataset-immutable", "formal-engine-unavailable"],
      status: "passed", artifact_adoption: false, wcag_certification: false
    }));
  } finally { await browser.close(); }
}

run().catch((error) => { console.error(error); process.exitCode = 1; });
