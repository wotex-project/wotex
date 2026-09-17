import assert from "node:assert/strict";
import test from "node:test";

import { ControlApiError, WotexLabClient } from "../dist/index.js";

const json = (body, init = {}) =>
  new Response(JSON.stringify(body), {
    status: init.status ?? 200,
    headers: { "content-type": "application/json", ...init.headers }
  });

test("catalogue operations use the generated paths without a bearer", async () => {
  const calls = [];
  const client = new WotexLabClient({
    baseUrl: "https://lab.example/api/v1/",
    fetch: async (url, init) => {
      calls.push({ url, init });
      return json({ scenarios: [] });
    }
  });

  assert.deepEqual(await client.listScenarios(), { scenarios: [] });
  await client.readScenario("thermal-nx");
  await client.readMetricsCatalogue();

  assert.deepEqual(
    calls.map(({ url }) => url),
    [
      "https://lab.example/api/v1/scenarios",
      "https://lab.example/api/v1/scenarios/thermal-nx",
      "https://lab.example/api/v1/metrics/catalogue"
    ]
  );
  assert.ok(calls.every(({ init }) => init.headers.authorization === undefined));
  assert.ok(calls.every(({ init }) => init.signal instanceof AbortSignal));
});

test("evidence is digest-escaped and bearer-bound", async () => {
  let request;
  const client = new WotexLabClient({
    baseUrl: "http://127.0.0.1:4000/api/v1",
    sessionToken: "0123456789abcdef",
    fetch: async (url, init) => {
      request = { url, init };
      return json({ schema_version: "1.0.0" });
    }
  });

  const digest = `sha256:${"a".repeat(64)}`;
  await client.readEvidence(digest);
  assert.equal(request.url, `http://127.0.0.1:4000/api/v1/evidence/sha256%3A${"a".repeat(64)}`);
  assert.equal(request.init.headers.authorization, "Bearer 0123456789abcdef");

  const anonymous = new WotexLabClient({
    baseUrl: "http://127.0.0.1:4000/api/v1",
    fetch: async () => assert.fail("missing bearer must fail before fetch")
  });
  await assert.rejects(anonymous.readEvidence(digest), /sessionToken is required/);
});

test("structured API errors and response ceilings fail closed", async () => {
  const denied = new WotexLabClient({
    baseUrl: "https://lab.example/api/v1",
    fetch: async () => json({ code: "unknown_session", phase: "session", message: "denied" }, { status: 403 })
  });

  await assert.rejects(denied.listScenarios(), (error) => {
    assert.ok(error instanceof ControlApiError);
    assert.equal(error.status, 403);
    assert.equal(error.body.code, "unknown_session");
    return true;
  });

  const oversized = new WotexLabClient({
    baseUrl: "https://lab.example/api/v1",
    maxResponseBytes: 16,
    fetch: async () => json({ value: "too large" })
  });
  await assert.rejects(oversized.listScenarios(), /response exceeds maxResponseBytes/);
});

test("constructor admission rejects credentials and unbounded options", () => {
  assert.throws(
    () => new WotexLabClient({ baseUrl: "https://user:secret@lab.example/api/v1" }),
    /must not contain credentials/
  );
  assert.throws(
    () => new WotexLabClient({ baseUrl: "file:///tmp/api/v1" }),
    /must use HTTP or HTTPS/
  );
  assert.throws(
    () => new WotexLabClient({ baseUrl: "https://lab.example/api/v1?tenant=other" }),
    /must not contain a query or fragment/
  );
  assert.throws(
    () => new WotexLabClient({ baseUrl: "https://lab.example/api/v1", deadlineMs: 60_001 }),
    /deadlineMs is outside/
  );
  assert.throws(
    () => new WotexLabClient({ baseUrl: "https://lab.example/api/v1", maxResponseBytes: 1_048_577 }),
    /maxResponseBytes is outside/
  );
});

test("run reads and mutations are bearer-bound and carry the idempotency identity", async () => {
  const requests = [];
  const run = { id: "run-1", status: "awaiting_approval" };
  const client = new WotexLabClient({
    baseUrl: "http://127.0.0.1:4000/api/v1",
    sessionToken: "0123456789abcdef",
    deadlineMs: 45_000,
    fetch: async (url, init) => {
      requests.push({ url, init });
      return json(run, { status: init.method === "POST" && url.endsWith("/runs") ? 201 : 200 });
    }
  });

  assert.deepEqual(await client.readRun("run-1"), run);
  await client.startRun(
    { experimentId: "smart_room", parameters: { meter: "on" } },
    { idempotencyKey: "start-1" }
  );
  await client.cancelRun("run/1", { idempotencyKey: "cancel-1" });

  const decision = {
    id: "decision-1",
    status: "granted",
    thing_id: "urn:wotex:lab:actuator",
    action_name: "setTarget",
    input: 20.5,
    proposal_digest: `sha256:${"b".repeat(64)}`,
    state_revision: 1,
    expires_at: 120_000
  };
  await client.approveDecision("run-1", decision, { idempotencyKey: "approve-1" });

  const [read, start, cancel, approve] = requests;
  assert.equal(read.init.method, "GET");
  assert.equal(read.url, "http://127.0.0.1:4000/api/v1/runs/run-1");
  assert.equal(read.init.headers.authorization, "Bearer 0123456789abcdef");

  assert.equal(start.init.method, "POST");
  assert.equal(start.init.headers["content-type"], "application/json");
  assert.equal(start.init.headers["idempotency-key"], "start-1");
  assert.deepEqual(JSON.parse(start.init.body), {
    experiment_id: "smart_room",
    parameters: { meter: "on" },
    deadline_ms: 30_000
  });

  assert.equal(cancel.url, "http://127.0.0.1:4000/api/v1/runs/run%2F1/cancel");
  assert.deepEqual(JSON.parse(cancel.init.body), { deadline_ms: 30_000 });

  assert.equal(approve.url, "http://127.0.0.1:4000/api/v1/runs/run-1/approval");
  assert.deepEqual(JSON.parse(approve.init.body), {
    decision_id: "decision-1",
    thing_id: "urn:wotex:lab:actuator",
    action_name: "setTarget",
    input: 20.5,
    proposal_digest: `sha256:${"b".repeat(64)}`,
    state_revision: 1,
    expires_at: 120_000,
    deadline_ms: 30_000
  });
});

test("mutation admission fails before fetch", async () => {
  const client = new WotexLabClient({
    baseUrl: "https://lab.example/api/v1",
    sessionToken: "0123456789abcdef",
    fetch: async () => assert.fail("refused mutations must not reach fetch")
  });

  await assert.rejects(client.startRun({ experimentId: "thermal" }, {}), /idempotencyKey is malformed/);
  await assert.rejects(
    client.startRun({ experimentId: "thermal" }, { idempotencyKey: "has space" }),
    /idempotencyKey is malformed/
  );
  await assert.rejects(client.startRun({}, { idempotencyKey: "k" }), /experimentId is required/);
  await assert.rejects(
    client.startRun({ experimentId: "thermal", parameters: { seed: 1 } }, { idempotencyKey: "k" }),
    /parameters must be an object of strings/
  );
  await assert.rejects(
    client.startRun({ experimentId: "thermal", parameters: { seed: "1".repeat(4_100) } }, { idempotencyKey: "k" }),
    /parameters must be an object of strings/
  );
  await assert.rejects(
    client.approveDecision("run-1", { id: "d", thing_id: "t".repeat(4_100) }, { idempotencyKey: "k" }),
    /request body exceeds 4096 bytes/
  );
  await assert.rejects(client.approveDecision("run-1", null, { idempotencyKey: "k" }), /decision is required/);

  const anonymous = new WotexLabClient({
    baseUrl: "https://lab.example/api/v1",
    fetch: async () => assert.fail("missing bearer must fail before fetch")
  });
  await assert.rejects(anonymous.readRun("run-1"), /sessionToken is required/);
  await assert.rejects(anonymous.cancelRun("run-1", { idempotencyKey: "k" }), /sessionToken is required/);
});

test("metric history queries post the closed descriptor with the session bearer", async () => {
  let request;
  const answer = { source: "ets_history", instance: "room-1", points: [{ t: 1, value: 2 }] };
  const client = new WotexLabClient({
    baseUrl: "http://127.0.0.1:4000/api/v1",
    sessionToken: "0123456789abcdef",
    fetch: async (url, init) => {
      request = { url, init };
      return json(answer);
    }
  });

  const query = {
    metric: "nx_duration_seconds",
    aggregation: "histogram_quantile",
    startAt: "2026-01-01T00:00:00Z",
    endAt: "2026-01-01T00:05:00Z",
    stepMs: 5_000,
    filters: { profile: "thermal" },
    quantile: 0.95
  };

  assert.deepEqual(await client.queryMetrics(query), answer);
  assert.equal(request.url, "http://127.0.0.1:4000/api/v1/metrics/query");
  assert.equal(request.init.method, "POST");
  assert.equal(request.init.headers.authorization, "Bearer 0123456789abcdef");
  assert.equal(request.init.headers["content-type"], "application/json");
  assert.equal(request.init.headers["idempotency-key"], undefined);
  assert.deepEqual(JSON.parse(request.init.body), {
    schema_version: "1.0.0",
    metric: "nx_duration_seconds",
    aggregation: "histogram_quantile",
    start_at: "2026-01-01T00:00:00Z",
    end_at: "2026-01-01T00:05:00Z",
    step_ms: 5_000,
    filters: { profile: "thermal" },
    quantile: 0.95
  });

  await assert.rejects(client.queryMetrics({ ...query, stepMs: 1_000 }), /stepMs is outside/);
  await assert.rejects(client.queryMetrics({ ...query, quantile: 1 }), /quantile must lie/);
  await assert.rejects(client.queryMetrics({ ...query, filters: ["profile"] }), /filters must be/);
  await assert.rejects(client.queryMetrics({ ...query, metric: "" }), /metric is malformed/);
  await assert.rejects(client.queryMetrics(null), /query is required/);
  await assert.rejects(
    client.queryMetrics({ ...query, filters: Object.fromEntries([...Array(16)].map((_, i) => [`${"k".repeat(125)}${i}`, "v".repeat(128)])) }),
    /request body exceeds 4096 bytes/
  );

  const anonymous = new WotexLabClient({
    baseUrl: "http://127.0.0.1:4000/api/v1",
    fetch: async () => assert.fail("missing bearer must fail before fetch")
  });
  await assert.rejects(anonymous.queryMetrics(query), /sessionToken is required/);
});
