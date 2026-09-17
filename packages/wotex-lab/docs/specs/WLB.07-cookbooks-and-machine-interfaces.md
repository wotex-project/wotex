# WLB.07: Executable cookbooks and machine interfaces

Specification version: 0.4.5. Contract: accepted. Source status: the sixteen
executable cookbooks under `priv/cookbooks/`, the `Wotex.Lab.Cookbook`
catalogue, the runner evidence in `test/wotex/lab/cookbook_test.exs`, the
`Wotex.Lab.Graph` generator with its nine representations and the
`bin/check_graph.exs` gate, and the MCP server core with stdio and Streamable
HTTP transports are implemented. The optional Workbench serves the four
read-only operations in the generated OpenAPI document at `/api/v1`; static
catalogue reads are inert and evidence lookup is bearer-bound to the caller's
existing room. Fifteen notebooks have executable workspace source evidence,
including Axon/EXLA training and formal-control vectors; `nerves-and-mcp`
retains partial evidence because its checked-in rpi4 host has no released
firmware or on-device record. This does not promote notebook installation to
artifact acceptance. The zero-runtime-dependency `@wotex/lab-client` source,
declarations, schema-drift gate, Node tests and npm archive-content check are
implemented under `clients/typescript/`; publication and installed-artifact
adoption remain separate. Mutation control operations remain planned. WLB.12
owns the generated ecosystem documentation and public static site.

## Cookbook catalogue

Every row is required in the accepted programme. Each Livebook has the same
automated scenario definition; prose MUST NOT be the sole executable source.

| ID | Experience | Contract evidence |
| --- | --- | --- |
| parse-td | Parse/validate/encode TD and TM, structured errors | WTX-C01–C04 |
| thermal-nx | Observations, unit callback, batch, defn, inert proposal | WNX-C03/C04; WLB.03 foundation |
| window-anomaly | Time/quality/mask/error and anomaly threshold experiments | WNX-C01/C02/C04 |
| serving-batches | Inline and supervised Nx.Serving | WNX-C04/C05 |
| axon-room-model | Reproducible synthetic training and held-out evaluation | WLB.03 |
| consume-http | Property read through Req and Runtime | RT-C04; WBH-C04 |
| write-and-act | Write/Action, status/content type/deadline rejection | RT-C02/C03; WBH-C01/C03 |
| observe-sse | Real frames, receiver death, reconnect, duplicate stop | RT-C02/C04; WBH-C02–C04 |
| consume-mqtt | Retained read, publish, subscriptions, loss/overload | WBM-C01–C04 |
| expose-thing | Explicit ingress policy and exact handler boundary | RT-C03 |
| directory | Both stores, conflict, paging, expiry and context | WTD-C01–C04 |
| continuum | Compatibility, values, disconnect/replay and inert intent | WCT-C01–C04 |
| conformance | Independent target and distinct failure outcomes | WCF-C01–C04 |
| smart-room | Discovery to numeric proposal to explicit simulated effect | WLB.03–WLB.06 |
| formal-control | Conflicting rules, bounded search and counterexample replay | WLB.09 |
| nerves-and-mcp | Bootable target plus explicit assistant access | WLB.07/WLB.08 |

Every notebook MUST include goal, prerequisites, package/consumer ownership,
run cells, expected output, deliberate breakage, safe telemetry, public seam,
exact spec/completion IDs and replacement adapter instructions. A consumer
must see the underlying package calls beside convenience APIs. Dependency
installation uses published packages or exact admitted artifacts; first-run
notebooks cannot depend on a Git checkout. The foundation README example is
local development documentation and does not claim this notebook gate.

The four disposable HTTP/SSE cookbook servers use per-evaluation function
plugs and ephemeral loopback ports. Repeating or overlapping these examples
MUST NOT redefine shared named modules or generate module atoms per run.
The source runner accepts catalogue IDs, not arbitrary submitted code. Caller
bindings, including values named `lab` or `tmp_dir`, MUST NOT authorize process
shutdown or filesystem deletion; notebooks explicitly close their owned
resources. A temporary-directory prefix is not ownership evidence. These
source tests do not prove isolation of arbitrary notebook code, cleanup after
timeout, or reclamation of unlinked processes/global telemetry handlers. Those
lifecycle obligations and clone-free installation remain independently required.

Data exploration follows the
[interactive analytics decision](../decisions/0005-interactive-elixir-analytics.md):
Explorer computes bounded dataframe results, Nx handles numerical algorithms,
and renderer-neutral chart descriptors feed the separate presentation layer.
Notebooks must expose executable Elixir queries, not require an archived
`kino_explorer` Smart Cell. Core Kino tables receive at most the admitted
preview; custom paging is a Lab adapter, not an upstream replacement claim.
Reactive notebook inputs re-evaluate admitted queries and keep source/query
identity visible. The notebook and workbench must agree on missing values,
units, filters, summary counts and transfer limits.

## Generated knowledge graph

A single versioned JSON source graph MUST join package archive metadata,
catalogues, public callback documentation and Lab scenario/adapter descriptors.
Inputs use digests and canonical revision-specific source URLs; no network
fetch occurs while loading the library. The generator MUST reject unresolved
IDs/paths/callbacks, duplicate IDs, cycles in required scenario steps and
undeclared ownership changes. Static source snapshots remain marked snapshots.

Required representations are `/.well-known/wotex`, `/manifest.json`,
`/manifest.jsonld`, `/ecosystem.ttl`, `/fixtures/index.json`, `/docs-index.jsonl`,
`/openapi.json`, `/asyncapi.yaml`, `/llms.txt`. These are accepted endpoint
paths, not claims of existing deployments. JSON-LD and RDF 1.1 Turtle describe
the graph; they do not add TD parsers to core. ExDoc Markdown and llms output
feed the index. OpenAPI 3.2.0 describes the Lab HTTP control API; AsyncAPI 3.1.0
describes exposed event/MQTT interfaces. Neither replaces TDs. Generators MUST
validate their selected schema dialect and pin tool versions; unsupported
codegen dialects require a loss-checked compatibility projection.

Each fixture manifest MUST name media type, license/provenance, input and
expected-output digests, positive/negative vector IDs, spec/seam/operation IDs
and scenario. Expected outputs cannot be exposed to the conformance target.
Generated TypeScript/npm `@wotex/lab-client` controls Lab via the control schema;
it MUST NOT become another WoT semantics implementation.
`bin/generate_typescript_client.exs` loss-checks the pinned OpenAPI dialect,
operation IDs, base path and admitted schema fields before regenerating the ESM
runtime and declarations. The client bounds deadlines and JSON response bytes,
escapes path segments, rejects URL credentials and sends a bearer only to the
evidence operation. Its injected Fetch seam is testability, not an alternate
transport contract.

Retrieval evaluations MUST ask who owns redirects, reconnect, supervision,
remote contexts, Directory storage, Nx effects, Continuum intent and formal
verification. Answers must resolve package, spec, seam, ownership, canonical
source and fixture IDs. Status assertions must preserve WLB.06's axes; an AI
response without source resolution cannot pass this test.

## Control plane and MCP

The default UI is the lean Phoenix LiveView workbench in
[WLB.11](WLB.11-workbench-and-design-system.md). Metrics queries and on-demand
BeamLens investigations follow [WLB.10](WLB.10-metrics-storage-and-ai-inspection.md).
MCP query tools use that same scoped descriptor; they do not grant arbitrary
SQL, PromQL, process introspection or provider credentials to an assistant.

Web/CLI/Livebook/MCP MUST use the same admitted scenario and evidence contract.
MCP supports pinned standard stdio and Streamable HTTP transports. Resources
expose package/spec/seam/scenario/Thing/evidence metadata. Tools support parse,
validate, explain error, list/discover/read simulated Things, bounded conformance
and benchmark jobs, and seam explanations. Long jobs have quotas, cancellation
and bounded retained output; read-oriented is not permission for unlimited work.
`Wotex.Lab.MCP.Server` is the transport-independent core pinned to protocol
version 2025-11-25, `Wotex.Lab.MCP.Stdio` the newline-delimited stdio
transport and `Wotex.Lab.MCP.Plug` the Streamable HTTP transport behind the
optional Plug requirement (origin allowlist, random `Mcp-Session-Id`,
expiring sessions, body ceiling, no server push). Resources embed the
catalogue, completion plan and provenance at compile time and expose fixture
and model manifests, design tokens, the seam table, the admitted scenario
descriptors of WLB.02 and the simulated Things of the session's explicit
instance. Tools are `parse_td`, `parse_tm`,
`explain_error`, `list_things`, `read_property`, `conformance_observe`,
`explain_seam` and `verify_control_model`; every call is bounded by per-call
limits and per-session call and output quotas. Benchmark jobs and the shared
metrics query descriptor remain planned.

Writes/Actions require explicit instance opt-in and per-request authorization.
`invoke_action` is listed only when the host built the session with
`writes: true` and a token of at least sixteen bytes; each call presents that
token, a session-unique idempotency key and a bounded deadline, targets a
simulated Thing of that instance only and dispatches through the runtime with
the credential port the host supplied.
Remote mutation requires a target bound to that disposable instance, operation
and schema admission, origin/auth checks, anti-replay identity, deadline and
rate/body/concurrency limits. The hosted default allows no external device
targets, arbitrary URL fetch, arbitrary filesystem path, model download or
raw Maude code. MCP cannot retrieve raw credentials. TLS, DNS/IP/redirect
egress controls, tenant isolation and session expiry are host responsibilities
with negative tests. A selected checkbox is not an Action authorization.

## Public adoption surface

The site and organisation profile MUST route by task: use/expose a Thing,
numerical experiments, infrastructure and evidence. One page shows the package
graph, ownership seams and actual readiness; run links exist only for admitted
artifacts. Package README links point to the exact relevant Lab cookbook.
Cross-repository/site publication is maintainer-owned and does not change Lab
semantics. Every generated link and documented command must pass a deployed
or artifact smoke check before being labeled available.
