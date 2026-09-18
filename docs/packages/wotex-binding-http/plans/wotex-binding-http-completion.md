# Wotex HTTP binding completion contract

Plan `WBH-C@1.1.0`; package baseline `wotex_binding_http 0.1.0`. This tracked
plan owns durable scope, prerequisites and acceptance criteria, not mutable
status. Catalogue `docs/packages/wotex-binding-http/specs/catalogue.yaml` owns
specification identities. Revision changes preserve historical Git evidence
rather than rewriting it.

Revision 1.1.0 records the package's move into the `wotex` repository without
changing any obligation. Documentation now lives under
`docs/packages/wotex-binding-http/`. Package archives no longer ship Markdown
documentation, governance files or agent files; specifications are published
through HexDocs. Fixtures and machine-read provenance ship under `priv/`. The
repository-level gate `WOTEX_PATH_DEPS=1 mix check --no-retry`, run from
`packages/wotex-binding-http`, and the package's CI lane now discharge
`repository_green` and `archive_consumer_green`. Tags use
`wotex-binding-http-v<version>`.

## Boundary and compatibility

HTTP owns message mapping, credential-free protocol values and framed SSE
adaptation. Wotex owns TD terminology/values; Runtime owns interaction selection
and explicit subscription supervision. The consumer client owns network I/O,
TLS/DNS/redirects, timeouts, framing, pools, backpressure and reconnection. The
consumer host owns policy and canonical Thing/Action/Event state. No server,
framework, pool, process, credential store or global registry is added here.

The package declares `wotex ~> 0.1.0`, `wotex_runtime ~> 0.1.0`, Jason and
Elixir `~> 1.18`; inspect exact Mix/lock inputs for each evidence run. Local
path overrides do not prove registry dependency availability. Error codes,
callback tuples, limits, header precedence, Action locators and SSE config
identity are compatibility surfaces. Broad Elixir/OTP support requires a tested
matrix, not inference from a version constraint.

## Stable work packages

| ID | Prerequisites | Deliverable | Acceptance |
|---|---|---|---|
| WBH-C01 | WBH.01–03 and declared core/Runtime interfaces | Source-to-operation/standards vector inventory | Every nine-operation Form cell and unsupported aggregate cell mapped; defaults attributed to exact authority |
| WBH-C02 | WBH-C01 | Client/SSE failure and lifecycle closure | Wrong returns, exceptions, failed handshake cleanup, concurrent/duplicate close, config transplant and receiver failure tested; no implicit connection owner |
| WBH-C03 | WBH-C01 | Limits and security boundary proof | Threshold bytes, header/URI cardinality, JSON allocation, event overload, deadline/redirect credential audience and redaction covered; consumer obligations explicit |
| WBH-C04 | WBH-C02, WBH-C03 | Exact archive and independent reference consumer | No live dependency source; real Runtime lifecycle with supplied client proves open/delivery/stop and negative cells |
| WBH-C05 | WBH-C04 | Public release candidate | Metadata/license/security, default dependency graph, docs links and claim matrix complete; no private/local archive content |
| WBH-C06 | WBH-C05 | Compatibility candidate | Promised mappings, values, callbacks, errors, and defaults have positive, negative, and boundary behavior vectors plus an explicit migration decision |

## Five evidence gates

Evidence binds exact source tree, direct/transitive dependency revisions or
archives, command/configuration, vector set, result and limitations. No gate
authorizes automated publication, tags or Git remote operations.

| Gate | Evidence requirement | Nonclaim |
|---|---|---|
| `repository_green` | The repository-level gate `WOTEX_PATH_DEPS=1 mix check --no-retry`, run from `packages/wotex-binding-http` and mirrored by the package's CI lane, passes warnings-as-errors compilation, locked and unused-dependency checks, formatting, dependency and Hex audits, strict Credo, Doctor, docs with warnings as errors, coverage, Dialyzer, the archive check and a whitespace diff | Not independent install or full protocol conformance |
| `archive_consumer_green` | `bin/check_archive.exs`, run by the same gate and CI lane, builds each exact archive once without path overrides, inspects and extracts those same bytes, then compiles a separate Mix consumer whose Wotex dependency, compile-source, BEAM and code paths exclude every live checkout | Not full lifecycle behavior |
| `reference_consumer_green` | That external consumer exercises WBH-A01..A06 through public APIs, including a supplied client and consumer-owned Runtime supervisor | No production transport certification |
| `public_release_candidate` | Previous gates (whose repository-level gate already carries the dependency audits, documentation, coverage and Dialyzer checks) plus boundary, package metadata/license/security, and claim review pass | Not registry availability, runtime matrix, or permission to publish |
| `stable_api_candidate` | Consumer-visible compatibility behavior and documented API changes receive review against WBH-C06 | Not a published release, serialized ABI, runtime matrix, or universal HTTP/WoT compliance |

`mix pkg wotex-binding-http test` and
`mix check.fast --package wotex-binding-http` remain the fast loop. The archive
helper supplies exact dependency reconstruction and reference-consumer
semantics. Compatibility tests assert
observable mappings, callbacks, messages, defaults, limits, results, errors,
redaction, and lifecycle behavior without enumerating every export, struct key,
test name, documentation row, or developer-gate entry.

## Standards-claim matrix

| Claim | Baseline source | Evidence under `test/wotex/binding/http/` | Scope |
|---|---|---|---|
| HTTP defaults for read/write/invoke | TD 1.1 Recommendation 2023-12-05 | `operation_inventory_test.exs`, `form_test.exs` | Three TD defaults and explicit method handling |
| Action status and SSE mappings | WoT Profiles Working Draft 2025-11-04 | `operation_inventory_test.exs`, `form_test.exs`, `transport_test.exs` | Package behavior, not Profile conformance |
| Fields/status/representation | RFC 9110, RFC 8259 | `value_test.exs`, `form_test.exs`, `transport_test.exs`, `limits_security_test.exs` | Validated and bounded values/JSON; no HTTP client implementation |
| Message framing | RFC 9112 | Client boundary tests | Client-owned, not implemented here |
| SSE adaptation | HTML Living Standard, repository observation 2026-09-02 | `client_lifecycle_inventory_test.exs`, `integration_test.exs`, `transport_test.exs` | Already-framed events; no parser/reconnect claim |
| Binding Registry membership | Draft Registry 2025-11-04 baseline | No registration evidence | No membership or W3C endorsement claim |

Exact primary links and maturity labels are in
`docs/packages/wotex-binding-http/standards-baseline.md`.
These are dated repository baselines, not freshly revalidated current maturity.
Newer draft text does not silently change a released mapping.

| Claim dimension | Current status | Promotion evidence |
|---|---|---|
| Value support | HTTP request/response/header/SSE values have named repository evidence | WBH-C01/03 close all fields, limits and invalid cases |
| Operation support | Three defaults and the catalogue's exact HTTP/SSE cells only | Per-operation positive/negative mapping and lifecycle vectors |
| Independent interoperability | Exact three-archive external consumer covers WBH-A01..A06 | Production-client interoperability remains external evidence |
| Profile conformance | Not established; draft-derived mappings are package behavior | Revision-pinned WoT Profile assertion corpus |
| External certification | None | External certification artifact; no internal gate substitutes for it |

## Remaining-claim ledger

| ID | Unsupported/unproven claim | Disposition |
|---|---|---|
| WBH-R01 | Exactly-once remote close / reconnect durability | Consumer session contract; WBH-C02 documents failure cells |
| WBH-R02 | Bounded total memory or stream mailbox | WBH-C03 proves local admission and a configured Runtime receiver boundary; client/owner mailboxes and total heap remain nonclaims |
| WBH-R03 | SSRF protection or safe cross-origin credential forwarding | WBH-C03 proves the separate port seam only; consumer client/host owns destination and audience policy |
| WBH-R04 | All TD operations or non-JSON content | Outside nine-operation profile; new reviewed mapping required |
| WBH-R05 | Full WoT Profile/Registry/HTTP client conformance | Explicit nonclaim; no badge or label upgrade from test count |
| WBH-R06 | Whole declared runtime matrix and registry installation | WBH-C05 pins one exact QA pair and proves the archive dependency graph; actual registry installation and a broader matrix remain promotion evidence |
| WBH-R07 | Local tracker exclusion from archive | Inspect every candidate archive and reject any Markdown documentation, governance, agent-file or `docs/tasks/local/` member |

WBH-C06 keeps the documented `0.1.0` operations, callback and receiver tuples,
error identities, defaults, limit measurements, mappings, and value accessors.
It requires no consumer migration. A future incompatible change requires a
reviewed WBH specification, compatibility-vector update, and package-version
decision; a newer draft does not silently change the package mapping.

## Local evidence contract

Optional file: a tracker under the ignored root
`docs/tasks/local/wotex-binding-http/`.
Schema is `schema_version: "1.0.0"`, `package`, `source_commit`,
`dependency_digests`, `items`.
Items keyed by WBH-C/WBH-R IDs carry `state`, `evidence`, `limitations`,
`next_action`; each evidence names gate, command, result and artifact digest.
No mutable status, worker assignment, attempts or approvals enter tracked
specifications/plans or package output. Unknown is not passed.

Package inputs ship no Markdown documentation and structurally exclude
`docs/tasks/local/`. Every candidate archive still proves the exclusion; Git
ignore alone never counts. A clean checkout requires no local tracker or
external automation service to build, test or select a normative task.

Fresh checkout procedure: clone the repository; read the root `CLAUDE.md`,
`packages/wotex-binding-http/CLAUDE.md`, this plan and the owning WBH files;
run `mix setup` from the repository root, use `mix pkg wotex-binding-http test`
and `mix check.fast --package wotex-binding-http` for the fast loop, and run
`mix pkg wotex-binding-http check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-binding-http`)
before recording `repository_green`.
