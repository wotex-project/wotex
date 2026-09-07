# WLB.02: Scenarios and reference components

Specification version: 0.1.0. Contract: accepted.

## Public descriptor foundation

`Wotex.Lab.Scenario.new/1` returns a validated value or `Wotex.Lab.Error`.
Inputs are the unique, closed keywords `id`, `title`, `capabilities`, `seed`,
`max_steps`. Every field is required. ID follows WLB.01; title is 1–256 valid
UTF-8 bytes; capabilities are 1–64 distinct ID strings; seed is an integer in
0–4,294,967,295; steps is an integer in 1–100,000. `to_map/1` is an accessor for
accepted values and emits these fields plus `schema_version: "1.0.0"`, using
string keys. It is not a remote admission function. Any execution boundary MUST
reconstruct and validate input, including manually forged structs.

The descriptor is serializable intent. It MUST NOT contain modules, callbacks,
PIDs, credentials or executable strings. Network input MUST NOT create atoms.
Construction does not execute steps, enforce a runtime timeout or seed global
random state. A descriptor cannot establish that its requested capability exists.

## Execution contract

1. The runner MUST accept an approved descriptor, a revision-pinned scenario
   definition and explicit host configuration. The definition supplies fixture
   digests, typed steps, exact Thing identities, required capabilities, ports,
   assertions, faults and upstream references. The host supplies trusted
   modules, instance, caller clock, random state, deadline and resource budget.
2. Preflight MUST reject unavailable capabilities, duplicate step IDs, unknown
   dependencies, cycles, invalid fixture digests and nonpositive budgets before
   starting a child. Unavailable components are `unsupported`, not pass.
3. A run progresses `admitted -> starting -> running -> stopping -> terminal`.
   Each admitted run receives a unique attempt ID even when the scenario and
   seed repeat. Terminal outcomes are `pass`, `fail`, `unsupported`, `timeout`,
   `cancelled`, `error`; cleanup failure cannot be hidden behind `pass`.
4. Budgets MUST include 60 s wall time, 100 steps, 128 children per role,
   1 MiB per ingress value, 1,024 queued deliveries, 100 reconnect attempts
   and 5 s cleanup by default, all explicitly overridable within profile
   ceilings. Preflight enforces ceilings. Monotonic deadlines control elapsed
   time; supplied observation time remains a separate coordinate.
5. Concurrent runs MUST isolate state, broker topic prefixes, repository
   contexts, temporary files, observers, random state and effect decisions.
   Cancellation, partial startup, callback raise/throw/exit, invalid callback
   return and receiver death MUST trigger bounded cleanup of owned resources.
   Error reasons are normalized and redacted. A late result cannot complete a
   new attempt. Repeated stop is idempotent; force-kill is recorded as such.
6. Replay MUST consume the recorded input/seed/version/decision stream. It may
   reproduce a logical result without reproducing scheduling or wall timings.
   A real network trace is not claimed deterministic because its seed repeats.

## Reference component port

`Wotex.Lab.Plugin` declares `id/0 :: String.t()`, `capabilities/0 :: [String.t()]`,
`child_specs/1 :: [Supervisor.child_spec()]`, `manifest/0 :: map()`. These are
trusted consumer callbacks. The host MUST explicitly select modules and validate
unique IDs/capabilities, required dependency versions and instance scope before
starting returned children. Plugin inspection MUST NOT open connections.

A manifest MUST identify the plugin version, capability IDs, package and
behaviour seams, secret-free configuration schema, process/resource ownership,
limits, fixture support, evidence references and cleanup contract. It MUST NOT
redefine W3C affordances or claim unsupported binding cells. HTTP, MQTT,
Directory, Nx.Serving, ex_maude, MCP, dashboard and BeamLens use this same port.
Extension activation is optional per instance, not optional programme completion.

For host-scoped integrations such as PromEx or BeamLens, the instance plugin
is a scoped bridge to an explicitly supplied host service. It MUST NOT start a
duplicate globally named dependency supervisor or mutate host application
configuration. Its manifest distinguishes instance children from external
service ownership, and instance shutdown revokes only its own access/handlers.
WLB.10 defines the trusted-host versus isolated-tenant boundary.

## Acceptance

`scenario_test.exs` covers the descriptor now. Runner acceptance additionally
requires identical CLI/Livebook/API descriptors; two concurrent runs; partial
startup unwind; exhausted limits; deterministic replay; callback failures;
duplicate stop; receiver death; and absence of leaked children/files/topics.
Plugin tests MUST use two independent host configurations with no environment
transplant. Catalogue status remains partial until all these obligations pass.
