defmodule Wotex.Lab.Check.TypeScriptClient do
  @moduledoc false

  @operations ~w(listScenarios readScenario readEvidence readMetricsCatalogue)
  @max_response_bytes 1_048_576

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
      |> Enum.flat_map(fn {_path, methods} -> Enum.map(methods, fn {_method, op} -> op end) end)
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
      "Error" => ~w(code message path phase)
    }

    Enum.each(expected, fn {name, fields} ->
      actual = schemas |> Map.fetch!(name) |> Map.fetch!("properties") |> Map.keys() |> Enum.sort()
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
  end

  defp package(version) do
    Jason.encode!(
      %{
        "name" => "@wotex/lab-client",
        "version" => version,
        "description" => "Generated read-only client for the WoTEx Lab control API",
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
    export interface ApiErrorBody { code: string; phase: string; path?: string | null; message: string; }
    export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;
    export interface ClientOptions { baseUrl: string; sessionToken?: string; deadlineMs?: number; fetch?: FetchLike; maxResponseBytes?: number; }
    export interface RequestOptions { signal?: AbortSignal; sessionToken?: string; }

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
    }
    """
  end

  defp javascript do
    """
    // Generated from Wotex.Lab.Graph.Interfaces. Do not edit by hand.
    const DEFAULT_DEADLINE_MS = 10_000;
    const DEFAULT_MAX_RESPONSE_BYTES = #{@max_response_bytes};

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
    """
  end

  defp typescript do
    """
    // Generated from Wotex.Lab.Graph.Interfaces. Do not edit by hand.
    export { ControlApiError, WotexLabClient } from "../dist/index.js";
    export type {
      ApiErrorBody,
      ClientOptions,
      EvidenceAssertion,
      EvidenceDependency,
      EvidenceRecord,
      FetchLike,
      MetricDefinition,
      MetricsCatalogue,
      RequestOptions,
      Scenario,
      ScenarioList
    } from "../dist/index.js";
    """
  end

  defp readme(version) do
    """
    # @wotex/lab-client

    Generated read-only client for the WoTEx Lab Workbench control API (#{version}).
    It implements the four operations in the checked OpenAPI 3.2 projection and
    has no runtime dependencies. Evidence reads require an existing session token;
    the client cannot create sessions, run experiments, write Properties or invoke Actions.

    ```js
    import { WotexLabClient } from "@wotex/lab-client";
    const lab = new WotexLabClient({ baseUrl: "http://127.0.0.1:4000/api/v1" });
    const { scenarios } = await lab.listScenarios();
    ```
    """
  end
end
