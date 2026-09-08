// Generated from Wotex.Lab.Graph.Interfaces. Do not edit by hand.
const DEFAULT_DEADLINE_MS = 10_000;
const DEFAULT_MAX_RESPONSE_BYTES = 1048576;

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

  async #request(path, options, protectedRoute) {
    const supplied = token(options.sessionToken, false);
    const capability = supplied ?? this.#sessionToken;
    if (protectedRoute && capability === undefined) throw new TypeError("sessionToken is required");
    const timeout = AbortSignal.timeout(this.#deadlineMs);
    const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout;
    const headers = { accept: "application/json" };
    if (protectedRoute) headers.authorization = `Bearer ${capability}`;
    const response = await this.#fetch(this.#baseUrl + path, { method: "GET", headers, signal });
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
