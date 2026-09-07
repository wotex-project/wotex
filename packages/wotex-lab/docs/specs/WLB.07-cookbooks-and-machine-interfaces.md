# WLB.07: Executable cookbooks and machine interfaces

Specification version: 0.1.0. Contract: accepted.

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

Writes/Actions require explicit instance opt-in and per-request authorization.
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
