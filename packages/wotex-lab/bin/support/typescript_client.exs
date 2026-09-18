defmodule Wotex.Lab.Check.TypeScriptClient do
  @moduledoc false

  @operations ~w(listScenarios readScenario readEvidence readMetricsCatalogue queryMetrics readRun startRun cancelRun approveDecision)
  @max_response_bytes 1_048_576
  @max_request_bytes 4_096

  @spec render(map(), String.t()) :: %{String.t() => String.t()}
  def render(openapi, license) when is_map(openapi) and is_binary(license) do
    validate!(openapi)
    version = get_in(openapi, ["info", "version"])

    %{
      "LICENSE" => license,
      "README.md" => readme(version),
      "package.json" => package(version),
      "dist/index.d.ts" => declarations(),
      "dist/index.js" => javascript(),
      "src/index.ts" => typescript()
    }
  end

  defp validate!(openapi) do
    openapi["openapi"] == "3.2.0" || raise "TypeScript projection requires OpenAPI 3.2.0"
    get_in(openapi, ["servers", Access.at(0), "url"]) == "/api/v1" || raise "server drift"

    operations =
      openapi["paths"]
      |> Enum.flat_map(fn {_, methods} -> Enum.map(methods, fn {_, op} -> op end) end)
      |> Enum.map(& &1["operationId"])
      |> Enum.sort()

    operations == Enum.sort(@operations) || raise "control operation drift"

    schemas = get_in(openapi, ["components", "schemas"])

    expected = %{
      "Scenario" => ~w(capabilities id max_steps schema_version seed title),
      "ScenarioList" => ~w(scenarios),
      "EvidenceRecord" =>
        ~w(assertions cleanup dependencies lock_digest outcomes source_tree_digest scenario_id schema_version revision attempt),
      "MetricsCatalogue" => ~w(metrics schema_version),
      "MetricQueryRequest" =>
        ~w(aggregation end_at filters metric quantile schema_version start_at step_ms),
      "MetricQueryAnswer" =>
        ~w(aggregation digest evidence freshness instance interval loss markers metric name points series_matched source unit),
      "Error" => ~w(code message path phase),
      "Run" =>
        ~w(assertions attempt decision duration_ms effect error experiment id record_digest started_at status),
      "Decision" =>
        ~w(action_name expires_at id input proposal_digest state_revision status thing_id),
      "StartRunRequest" => ~w(deadline_ms experiment_id parameters),
      "CancelRunRequest" => ~w(deadline_ms),
      "ApprovalRequest" =>
        ~w(action_name deadline_ms decision_id expires_at input proposal_digest state_revision thing_id)
    }

    Enum.each(expected, fn {name, fields} ->
      actual =
        schemas
        |> Map.fetch!(name)
        |> Map.fetch!("properties")
        |> Map.keys()
        |> Enum.sort()

      actual == Enum.sort(fields) || raise "#{name} schema drift"
    end)

    kinds =
      get_in(schemas, [
        "MetricsCatalogue",
        "properties",
        "metrics",
        "items",
        "properties",
        "kind",
        "enum"
      ])

    kinds == ~w(counter gauge histogram) || raise "metric kind drift"

    get_in(schemas, ["Run", "properties", "status", "enum"]) ==
      ~w(completed failed awaiting_approval dispatched cancelled) || raise "run status drift"

    get_in(schemas, ["DeadlineMs", "maximum"]) == 30_000 || raise "deadline bound drift"

    get_in(openapi, ["components", "parameters", "IdempotencyKey", "name"]) == "Idempotency-Key" ||
      raise "idempotency header drift"

    Enum.each(~w(StartRunRequest CancelRunRequest ApprovalRequest MetricQueryRequest), fn name ->
      get_in(schemas, [name, "additionalProperties"]) == false || raise "#{name} is not closed"
    end)
  end

  defp package(version) do
    Jason.encode!(
      %{
        "name" => "@wotex/lab-client",
        "version" => version,
        "description" => "Generated client for the WoTEx Lab control API",
        "type" => "module",
        "license" => "Apache-2.0",
        "sideEffects" => false,
        "files" => ["dist", "README.md", "LICENSE"],
        "main" => "./dist/index.js",
        "types" => "./dist/index.d.ts",
        "exports" => %{"." => "./dist/index.js"},
        "engines" => %{"node" => ">=20"},
        "scripts" => %{"test" => "node --test"}
      },
      pretty: true
    ) <> "\n"
  end

  defp declarations do
    """
    // Generated from Wotex.Lab.Graph.Interfaces. Do not edit by hand.
    export interface Scenario {
      schema_version: "1.0.0";
      id: string;
      title: string;
      capabilities: string[];
      seed: number;
      max_steps: number;
    }

    export interface ScenarioList { scenarios: Scenario[]; }

    export interface EvidenceAssertion { id: string; status: "pass" | "fail" | "unsupported" | "not_run" | "infrastructure_error"; }
    export interface EvidenceDependency { name: string; version: string; archive: `sha256:${string}` | "missing"; }
    export interface EvidenceRecord {
      schema_version: "1.0.0";
      scenario_id: string;
      revision: string;
      attempt: number;
      source_tree_digest: `sha256:${string}`;
      lock_digest: `sha256:${string}`;
      dependencies: EvidenceDependency[];
      assertions: EvidenceAssertion[];
      outcomes: Record<string, unknown>;
      cleanup: { status: "ok" | "failed" };
    }

    export interface MetricDefinition {
      name: string;
      unit: string;
      kind: "counter" | "gauge" | "histogram";
      dimensions?: string[];
    }
    export interface MetricsCatalogue { schema_version: string; metrics: MetricDefinition[]; }
    export type RunStatus = "completed" | "failed" | "awaiting_approval" | "dispatched" | "cancelled";
    export interface RunAssertion { id: string; status: "pass" | "fail" | "not_run"; note: string; }
    export interface Decision {
      id: string;
      status: string;
      thing_id: string;
      action_name: string;
      input: number;
      proposal_digest: `sha256:${string}`;
      state_revision: number;
      expires_at: number;
    }
    export interface Run {
      id: string;
      experiment: string;
      attempt: number;
      status: RunStatus;
      started_at: string;
      duration_ms: number;
      record_digest: `sha256:${string}` | null;
      assertions: RunAssertion[];
      decision: Decision | null;
      effect: unknown;
      error: { code: string; phase: string; message: string } | null;
    }
    export interface StartRunRequest { experimentId: string; parameters?: Record<string, string>; }
    export type MetricAggregation = "last" | "sum" | "min" | "max" | "avg" | "increase" | "rate" | "histogram_quantile";
    export interface MetricQuery {
      metric: string;
      aggregation: MetricAggregation;
      startAt: string;
      endAt: string;
      stepMs: number;
      filters?: Record<string, string>;
      quantile?: number;
    }
    export interface MetricPoint { t: number; value: number; }
    export interface MetricQueryAnswer {
      source: "ets_history";
      instance: string;
      metric: string;
      name?: string;
      unit: string;
      aggregation: MetricAggregation;
      interval: { start_ms: number; end_ms: number; step_ms: number };
      freshness: Record<string, number> | null;
      points: MetricPoint[];
      markers: Array<{ kind: string; t?: number } & Record<string, unknown>>;
      loss?: Record<string, number>;
      series_matched?: number;
      digest: `sha256:${string}`;
      evidence?: unknown[];
    }
    export interface ApiErrorBody { code: string; phase: string; path?: string | null; message: string; }
    export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;
    export interface ClientOptions { baseUrl: string; sessionToken?: string; deadlineMs?: number; fetch?: FetchLike; maxResponseBytes?: number; }
    export interface RequestOptions { signal?: AbortSignal; sessionToken?: string; }
    export interface MutationOptions extends RequestOptions { idempotencyKey: string; }

    export declare class ControlApiError extends Error {
      readonly status: number;
      readonly body: ApiErrorBody | null;
      constructor(status: number, body: ApiErrorBody | null);
    }

    export declare class WotexLabClient {
      constructor(options: ClientOptions);
      listScenarios(options?: RequestOptions): Promise<ScenarioList>;
      readScenario(id: string, options?: RequestOptions): Promise<Scenario>;
      readEvidence(recordId: `sha256:${string}`, options?: RequestOptions): Promise<EvidenceRecord>;
      readMetricsCatalogue(options?: RequestOptions): Promise<MetricsCatalogue>;
      queryMetrics(query: MetricQuery, options?: RequestOptions): Promise<MetricQueryAnswer>;
      readRun(runId: string, options?: RequestOptions): Promise<Run>;
      startRun(request: StartRunRequest, options: MutationOptions): Promise<Run>;
      cancelRun(runId: string, options: MutationOptions): Promise<Run>;
      approveDecision(runId: string, decision: Decision, options: MutationOptions): Promise<Run>;
    }
    """
  end

  defp javascript do
    """
    // Generated from Wotex.Lab.Graph.Interfaces. Do not edit by hand.
    const DEFAULT_DEADLINE_MS = 10_000;
    const DEFAULT_MAX_RESPONSE_BYTES = #{@max_response_bytes};
    const MAX_REQUEST_BYTES = #{@max_request_bytes};
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
        this.#baseUrl = url.toString().replace(/\\/$/, "");
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
        if (!options || typeof options.idempotencyKey !== "string" || !/^[\\x21-\\x7e]{1,128}$/.test(options.idempotencyKey)) {
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
    """
  end

  defp typescript do
    """
    // Generated from Wotex.Lab.Graph.Interfaces. Do not edit by hand.
    export { ControlApiError, WotexLabClient } from "../dist/index.js";
    export type {
      ApiErrorBody,
      ClientOptions,
      Decision,
      EvidenceAssertion,
      EvidenceDependency,
      EvidenceRecord,
      FetchLike,
      MetricAggregation,
      MetricDefinition,
      MetricPoint,
      MetricQuery,
      MetricQueryAnswer,
      MetricsCatalogue,
      MutationOptions,
      RequestOptions,
      Run,
      RunAssertion,
      RunStatus,
      Scenario,
      ScenarioList,
      StartRunRequest
    } from "../dist/index.js";
    """
  end

  defp readme(version) do
    """
    # @wotex/lab-client

    Generated client for the WoTEx Lab Workbench control API (#{version}).
    It implements the nine operations in the checked OpenAPI 3.2 projection and
    has no runtime dependencies. Evidence and run reads and `queryMetrics`, which
    reads the session room's attributed metric history, require an existing
    session token. `startRun`, `cancelRun` and `approveDecision` also require a Workbench
    host that opted into control mutations and a caller-chosen `idempotencyKey`;
    retry a request with the same key to learn its outcome without repeating it.
    The client cannot create sessions, write Properties or invoke an Action other
    than a decision the session room granted.

    ```js
    import { WotexLabClient } from "@wotex/lab-client";
    const lab = new WotexLabClient({ baseUrl: "http://127.0.0.1:4000/api/v1" });
    const { scenarios } = await lab.listScenarios();
    ```
    """
  end
end
