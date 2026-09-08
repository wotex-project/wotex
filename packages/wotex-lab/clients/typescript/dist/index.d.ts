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
