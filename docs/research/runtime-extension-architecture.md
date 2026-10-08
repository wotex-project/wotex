# Runtime extension architecture — research and specification update plan

Status: **research proposal, not accepted normative specification**

Date: 2026-10-08

Target: `wotex-project/wotex`

Research baseline reported: `e6192b1de7e9cbfc31417e116babb19cea2af220` (revalidate against current main before implementation)

## Decision to investigate

WoTEx currently uses independent Mix projects, with Hex as the default sibling dependency resolution and development-only path overrides. The packages are experimental and unpublished. **Hex is a package distribution and dependency mechanism, not an extension ABI.** No new architecture should be imposed merely because a plugin ABI is fashionable. The first task is to prove which extensions genuinely need runtime replacement, third-party loading, or language neutrality.

**Provisional recommendation:** retain Mix project boundaries and the option to publish trusted Elixir libraries on Hex; introduce an independent logical extension contract only if a concrete consumer use case requires runtime extensibility. For an external extension proof, evaluate supervised OS processes and versioned IPC first; evaluate WASM separately. Do not make dynamic BEAM code loading, WASM, or automatic Internet installation a baseline requirement.

## Evidence and existing contracts

- [README](https://github.com/wotex-project/wotex/blob/main/README.md): 18 independent Mix projects, experimental, no WoTEx Hex publication; consumers pin one repository commit.
- [Package graph](https://github.com/wotex-project/wotex/blob/main/docs/architecture/package-graph.md): Hex or dev-only path dependencies; explicit `Wotex.Runtime.Transport` and `Wotex.Runtime.Credentials`; no implicit discovery; consumer-owned supervision.
- [Native artifact foundation](https://github.com/wotex-project/wotex/blob/main/docs/architecture/native-artifact-contract.md): accepted v0.7.0 contract, closed inventory, canonical build/payload digests, admission/verification, target dependency closure, no build/download/autostart on library load.
- [Catalogue](https://github.com/wotex-project/wotex/blob/main/docs/catalogue.yaml): specification implementation status is not equivalent to extension-runtime conformance.
- [Documentation index](https://github.com/wotex-project/wotex/blob/main/docs/README.md): transport, protocol, runtime, credentials, and evidence boundaries.

No unified runtime extension manifest, admission state machine, negotiated extension ABI, upgrade protocol, or conformance suite was verified. This document proposes them for evaluation, not as implemented features.

## Critical decision: keep Hex, reduce packages, or replace packaging?

Evaluate **separately** (a) number of Mix applications, (b) source dependency resolution, (c) publishing to Hex, and (d) runtime execution.

| Option | Benefit | Cost | Decision gate |
|---|---|---|---|
| Keep independent Mix projects, dev paths, future Hex publication | Reuses OTP tooling, isolated API/version/tests, consumers choose protocols | Cross-project version coordination, release overhead | Keep boundaries only where independent consumers, dependency closure, or release cadence justify them |
| Collapse selected projects into fewer Mix applications | Faster refactors and fewer inter-package constraints during greenfield development | Less selective consumption, harder optional native dependencies | Prototype dependency/CI graph before merging; do not collapse just because unpublished |
| One umbrella | Coordinated development | Potentially unsuitable for independent distribution and selective consumers | Measure actual workflow friction first |
| Hex-only extensions | Lowest complexity for trusted BEAM | No runtime install, shared trust/VM | Sufficient when consumer deployment rebuilds are acceptable |
| Explicit BEAM adapter registration | Composable without runtime ABI | Compiled into release | Default until external loading is demonstrated necessary |
| External process IPC | Language neutrality, crash isolation, runtime replacement | Framing, protocol, OS sandbox, startup cost | Implement only with a real adapter needing it |
| WASM component binding | Portable, capability-shaped host surface | Toolchain and runtime complexity; hardware/native limits | Experimental, separately gated by benchmarks and conformance |

**Hex retention rationale:** Elixir dependency resolution, compile-time verification, OTP conventions, normal tooling, test helpers, selective protocol installation and eventual SDK distribution remain useful. **Hex publication is not required now**, and the 18-package count is not sacred. Publishing each experimental package prematurely is explicitly discouraged. Revisit per-package granularity using measured dependency, CI, and consumer evidence.

## Proposed extension contract (conditional target)

Define one *semantic* extension API independent of execution mechanism. Candidate bindings: `beam-v1` (trusted, in-release), `process-v1` (external supervised executable), and experimental `wasm-v1` only if justified.

Candidate manifest fields: `schema_version`, `id`, `version`, `kind`, `required_host_api`, `binding.type/version`, `entrypoint`, `artifact_refs`, `capabilities`, `permissions`, `configuration_schema`, `publisher`, `health`, `limits`.

Lifecycle: `discovered -> verified -> policy_checked -> admitted -> starting -> ready -> draining -> stopped`; explicit rejection, failure, restart budget, quarantine and rollback paths. **Discovery MUST NOT execute or download code.** Admission MUST verify exact payload identity, compatible schema/API/binding, and consumer authorization. Start MUST remain consumer-supervised and explicit. Version axes MUST be independent (extension version, manifest schema, semantic API, binding, native artifact contract, protocol interface). In-process BEAM code MUST NOT be described as securely sandboxed. An OS child process alone MUST NOT be described as a security sandbox. Untrusted capabilities MUST be denied by default; no ambient credentials.

The native artifact contract remains the source of truth for artifact identity, target compatibility and verified adoption. The extension manifest references it; it MUST NOT duplicate build identity or weaken verification. No implicit startup/download on package load. Existing transport and credential behavior interfaces remain authoritative for domain operations.

Upgrade proposal: verify candidate -> start and health-check candidate -> route switch -> drain old -> stop old; failure before switch retains old instance. State migration is optional and explicitly versioned. Avoid claiming atomicity for external device effects.

## Proposed spec files (do not treat as approved)

Follow the repository's existing package-scoped spec conventions rather than automatically creating a new framework package. Proposed research-stage files:

- `docs/research/runtime-extension-architecture.md` — this document.
- `docs/architecture/runtime-extension-decision.md` — ADR after evidence and approval.
- `docs/architecture/runtime-extension-contract.md` — normative semantic model if decision passes.
- `docs/architecture/extension-manifest.md` — schema and versioning.
- `docs/architecture/extension-security.md` — admission, trust, capability enforcement, threat model.
- `docs/architecture/extension-lifecycle.md` — state transitions, consumer supervision, upgrade/rollback.
- `docs/architecture/extension-bindings.md` — BEAM and process bindings, WASM experiment separately.
- `docs/architecture/extension-conformance.md` — executable vectors and evidence requirements.

Amend only relevant sections of existing `docs/architecture/package-graph.md`, `docs/architecture/native-artifact-contract.md`, runtime/transport/credential specifications, `docs/catalogue.yaml`, `tooling/packages.yaml` and CI **after** an ADR is accepted. The catalogue MUST distinguish `proposed`, `specified`, `partial`, `implemented`, and `evidence_verified`; no research proposal may be represented as implemented.

## Required tests and acceptance criteria

1. Existing BEAM adapters remain usable without extension manifests; no public behavior regression.
2. Deterministic manifest parsing, version negotiation, duplicate IDs, incompatible host API, unknown required fields.
3. Tampered payload, untrusted publisher, unsupported target, undeclared capability and denied credential all fail closed with typed errors.
4. Discovery never executes code or initiates network fetch.
5. Consumer explicitly owns child specs, supervision, shutdown and restart budgets.
6. Independent process extension fixtures exercise handshake, request correlation, framing bounds, cancellation, health, drain and crash recovery.
7. Candidate upgrade failures preserve old routing; successful cutover drains correctly; external effects are never replayed implicitly.
8. Native artifact verification and target closure still pass; no parallel artifact integrity model.
9. Tests exercise real protocol adapters (one pure BEAM, one native-backed), not only toy fixtures.
10. Benchmark latency, memory, cross-platform builds and developer iteration against existing Hex-only baseline.
11. WASM is accepted only if the same semantic conformance suite passes and operational benefits exceed added complexity.
12. CI and documentation distinguish verified results from pending hardware qualification.

## Migration plan and stop/go gates

**Phase 0 — inventory:** Audit all 18 projects, dependency graph, tests, existing native adapters, release pipeline and hardware evidence. Identify an actual external runtime extension consumer and a counterexample satisfied by compile-time registration. Output a gap matrix with file/line references.

**Phase 1 — ADR:** Compare Hex-only, fewer Mix packages, explicit BEAM registration, external process and WASM. Require evidence of independent consumer demand before adding an extension host. Decide whether package consolidation would reduce friction.

**Phase 2 — specifications only:** Approve semantic API, manifest, security, lifecycle, versioning, conformance and linkage to native artifact contract. Preserve consumer ownership.

**Phase 3 — BEAM compatibility slice:** Map one existing protocol adapter into the semantic contract without changing its public API; prove no mandatory runtime bundle for normal Hex consumers.

**Phase 4 — external process proof:** Implement two independent process extensions using the same wire contract, host-controlled supervision, deterministic verification and fault tests. Freeze wire encoding only after interoperability evidence.

**Phase 5 — catalogue/CI/release:** Schema validation, negative fixtures, native artifact linkage, target matrix, conformance evidence and migration guide. Release remains experimental until gates pass.

**Phase 6 — optional WASM:** Evaluate against the exact same semantic contract, security tests and benchmarks. Reject or defer without blocking the rest.

Rollback: retain existing package interfaces and deployment path throughout; the extension manager remains optional until conformance, security and real-consumer evidence justify default adoption. No code changes or publication are authorized by this research document.

## Research limitations and follow-up

This is an actionable synthesis of the completed Deep Research report and the directly inspected repository architecture. The complete historical plugin ABI document from other sessions was not recovered, so prior recommendations are **not** treated as accepted Wotex decisions. Research report's numeric preference scores and staffing estimates were subjective and are deliberately excluded from normative decisions. Exact spec-to-implementation coverage, all hardware test results, and whether each of the 18 projects should survive must be verified against current source before drafting normative changes.

## Sources

- https://github.com/wotex-project/wotex
- https://github.com/wotex-project/wotex/blob/main/docs/architecture/package-graph.md
- https://github.com/wotex-project/wotex/blob/main/docs/architecture/native-artifact-contract.md
- https://github.com/wotex-project/wotex/blob/main/docs/catalogue.yaml
- https://elixir-lang.org/getting-started/mix-otp/introduction-to-mix.html
- https://hexdocs.pm/elixir/Application.html
- https://docs.github.com/en/code-security/concepts/supply-chain-security/dependency-graph
