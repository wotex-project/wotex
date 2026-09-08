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
