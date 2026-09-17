// Generated from Wotex.Lab.Graph.Interfaces. Do not edit by hand.
const DEFAULT_DEADLINE_MS = 10_000;
const DEFAULT_MAX_RESPONSE_BYTES = 1048576;
const MAX_REQUEST_BYTES = 4096;
const MAX_BODY_DEADLINE_MS = 30_000;

export class ControlApiError extends Error {
  constructor(status, body) {
    super(body?.message ?? `WoTEx Lab control API returned HTTP ${status}`);
    this.name = "ControlApiError";
    this.status = status;
    this.body = body;
  }
}

export class WotexLabClient {
  #baseUrl;
  #deadlineMs;
  #fetch;
  #maxResponseBytes;
  #sessionToken;

  constructor(options) {
    if (!options || typeof options.baseUrl !== "string") throw new TypeError("baseUrl is required");
    const url = new URL(options.baseUrl);
    if (url.username || url.password) throw new TypeError("baseUrl must not contain credentials");
    if (!["http:", "https:"].includes(url.protocol)) throw new TypeError("baseUrl must use HTTP or HTTPS");
    if (url.search || url.hash) throw new TypeError("baseUrl must not contain a query or fragment");
    this.#baseUrl = url.toString().replace(/\/$/, "");
    this.#deadlineMs = integerBetween(options.deadlineMs ?? DEFAULT_DEADLINE_MS, 1, 60_000, "deadlineMs");
    this.#maxResponseBytes = integerBetween(options.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES, 1, DEFAULT_MAX_RESPONSE_BYTES, "maxResponseBytes");
    this.#fetch = options.fetch ?? globalThis.fetch;
    if (typeof this.#fetch !== "function") throw new TypeError("fetch is required");
    this.#sessionToken = token(options.sessionToken, false);
  }

  listScenarios(options = {}) { return this.#request("/scenarios", options, false); }
  readScenario(id, options = {}) { return this.#request(`/scenarios/${segment(id, "scenario id")}`, options, false); }
  readEvidence(recordId, options = {}) { return this.#request(`/evidence/${segment(recordId, "record id")}`, options, true); }
  readMetricsCatalogue(options = {}) { return this.#request("/metrics/catalogue", options, false); }
  readRun(runId, options = {}) { return this.#request(`/runs/${segment(runId, "run id")}`, options, true); }

  async queryMetrics(query, options = {}) {
    if (!query || typeof query !== "object") throw new TypeError("query is required");
    const body = {
      schema_version: "1.0.0",
      metric: text(query.metric, "metric"),
      aggregation: text(query.aggregation, "aggregation"),
      start_at: text(query.startAt, "startAt"),
      end_at: text(query.endAt, "endAt"),
      step_ms: integerBetween(query.stepMs, 5_000, Number.MAX_SAFE_INTEGER, "stepMs")
    };
    if (query.filters !== undefined) body.filters = filters(query.filters);
    if (query.quantile !== undefined) {
      if (typeof query.quantile !== "number" || !(query.quantile > 0 && query.quantile < 1)) throw new TypeError("quantile must lie between 0 and 1");
      body.quantile = query.quantile;
    }
    const encoded = JSON.stringify(body);
    if (new TextEncoder().encode(encoded).byteLength > MAX_REQUEST_BYTES) throw new RangeError("request body exceeds 4096 bytes");
    return this.#request("/metrics/query", options, true, { body: encoded });
  }

  async startRun(request, options) {
    if (!request || typeof request.experimentId !== "string") throw new TypeError("experimentId is required");
    const body = { experiment_id: request.experimentId };
    if (request.parameters !== undefined) body.parameters = parameters(request.parameters);
    return this.#mutate("/runs", body, options);
  }

  async cancelRun(runId, options) {
    return this.#mutate(`/runs/${segment(runId, "run id")}/cancel`, {}, options);
  }

  async approveDecision(runId, decision, options) {
    if (!decision || typeof decision !== "object") throw new TypeError("decision is required");
    const body = {
      decision_id: decision.id,
      thing_id: decision.thing_id,
      action_name: decision.action_name,
      input: decision.input,
      proposal_digest: decision.proposal_digest,
      state_revision: decision.state_revision,
      expires_at: decision.expires_at
    };
    return this.#mutate(`/runs/${segment(runId, "run id")}/approval`, body, options);
  }

  #mutate(path, body, options) {
    if (!options || typeof options.idempotencyKey !== "string" || !/^[\x21-\x7e]{1,128}$/.test(options.idempotencyKey)) {
      throw new TypeError("idempotencyKey is malformed");
    }
    const encoded = JSON.stringify({ ...body, deadline_ms: Math.min(this.#deadlineMs, MAX_BODY_DEADLINE_MS) });
    if (new TextEncoder().encode(encoded).byteLength > MAX_REQUEST_BYTES) throw new RangeError("request body exceeds 4096 bytes");
    return this.#request(path, options, true, { body: encoded, idempotencyKey: options.idempotencyKey });
  }

  async #request(path, options, protectedRoute, mutation) {
    const supplied = token(options.sessionToken, false);
    const capability = supplied ?? this.#sessionToken;
    if (protectedRoute && capability === undefined) throw new TypeError("sessionToken is required");
    const timeout = AbortSignal.timeout(this.#deadlineMs);
    const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout;
    const headers = { accept: "application/json" };
    if (protectedRoute) headers.authorization = `Bearer ${capability}`;
    const init = { method: "GET", headers, signal };
    if (mutation) {
      init.method = "POST";
      init.body = mutation.body;
      headers["content-type"] = "application/json";
      if (mutation.idempotencyKey !== undefined) headers["idempotency-key"] = mutation.idempotencyKey;
    }
    const response = await this.#fetch(this.#baseUrl + path, init);
    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().startsWith("application/json")) throw new ControlApiError(response.status, null);
    const body = await boundedJson(response, this.#maxResponseBytes);
    if (!response.ok) throw new ControlApiError(response.status, body);
    return body;
  }
}

function integerBetween(value, minimum, maximum, name) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) throw new TypeError(`${name} is outside its admitted bounds`);
  return value;
}

function segment(value, name) {
  if (typeof value !== "string" || value.length === 0 || value.length > 128) throw new TypeError(`${name} is malformed`);
  return encodeURIComponent(value);
}

function parameters(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError("parameters must be an object of strings");
  const entries = Object.entries(value);
  if (entries.length > 16 || !entries.every(([, item]) => typeof item === "string" && item.length <= 32)) {
    throw new TypeError("parameters must be an object of strings");
  }
  return Object.fromEntries(entries);
}

function text(value, name) {
  if (typeof value !== "string" || value.length === 0 || value.length > 128) throw new TypeError(`${name} is malformed`);
  return value;
}

function filters(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError("filters must be an object of strings");
  const entries = Object.entries(value);
  if (entries.length > 16 || !entries.every(([key, item]) => key.length <= 128 && typeof item === "string" && item.length <= 128)) {
    throw new TypeError("filters must be an object of strings");
  }
  return Object.fromEntries(entries);
}

function token(value, required) {
  if (value === undefined && !required) return undefined;
  if (typeof value !== "string" || value.length < 16 || value.length > 128) throw new TypeError("sessionToken is malformed");
  return value;
}

async function boundedJson(response, maximum) {
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maximum) throw new RangeError("response exceeds maxResponseBytes");
  if (!response.body) return null;
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maximum) throw new RangeError("response exceeds maxResponseBytes");
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel(error);
    throw error;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder().decode(bytes));
}
