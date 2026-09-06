# Wotex HTTP binding completion contract

Plan `WBH-C@1.0.0`; package baseline `wotex_binding_http 0.1.0`. This tracked
plan owns durable scope, prerequisites and acceptance criteria, not mutable
status. Catalogue `docs/specs/catalogue.yaml` owns specification identities.
Revision changes preserve historical Git evidence rather than rewriting it.

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
| WBH-C06 | WBH-C05 | Stable API candidate | All promised mappings/values/errors/defaults frozen with compatibility vectors and migration decisions |

## Five evidence gates

Evidence binds exact source tree, direct/transitive dependency revisions or
archives, command/configuration, vector set, result and limitations. No gate
authorizes automated publication, tags or Git remote operations.

| Gate | Evidence requirement | Nonclaim |
|---|---|---|
| `repository_green` | `WOTEX_PATH_DEPS=1 mix check --no-retry`, including skipped-tool handling, coverage, strict static checks, docs and boundary | Not independent install or full protocol conformance |
| `archive_consumer_green` | Build without path overrides; a separate minimal Mix consumer installs exact archives and exercises one HTTP mapping success plus typed rejection through public API, with no live source | Not full lifecycle behavior |
| `reference_consumer_green` | WBH-C04 against those archives with supplied client and Runtime supervisor | No production transport certification |
| `public_release_candidate` | Previous gates, actual archive exclusion, package metadata/license/security, clean dependency installation, claim review | Not permission to publish |
| `stable_api_candidate` | WBH-C06 compatibility/error/default/limit matrix, all promised cells proven | Not universal HTTP/WoT compliance |

The repository's `.check.exs` enables skipped-tool handling. A successful
invocation does not excuse a skipped mandatory tool: inspect every outcome.
Existing archive helpers remain supporting evidence; independent dependency
reconstruction and reference-consumer semantics need their own results.

## Standards-claim matrix

| Claim | Baseline source | Evidence under `test/wotex/binding/http/` | Scope |
|---|---|---|---|
| HTTP defaults for read/write/invoke | TD 1.1 Recommendation 2023-12-05 | `form_test.exs` | Three TD defaults and explicit method handling |
| Action status and SSE mappings | WoT Profiles Working Draft 2025-11-04 | `form_test.exs`, `transport_test.exs` | Package behavior, not Profile conformance |
| Fields/status/representation | RFC 9110, RFC 8259 | `value_test.exs`, `form_test.exs`, `transport_test.exs` | Validated values/JSON; no HTTP client implementation |
| Message framing | RFC 9112 | Client boundary tests | Client-owned, not implemented here |
| SSE adaptation | HTML Living Standard, repository observation 2026-09-02 | `integration_test.exs`, `transport_test.exs` | Already-framed events; no parser/reconnect claim |
| Binding Registry membership | Draft Registry 2025-11-04 baseline | No registration evidence | No membership or W3C endorsement claim |

Exact primary links and maturity labels are in `docs/standards-baseline.md`.
These are dated repository baselines, not freshly revalidated current maturity.
Newer draft text does not silently change a released mapping.

| Claim dimension | Current status | Promotion evidence |
|---|---|---|
| Value support | HTTP request/response/header/SSE values have named repository evidence | WBH-C01/03 close all fields, limits and invalid cases |
| Operation support | Three defaults and the catalogue's exact HTTP/SSE cells only | Per-operation positive/negative mapping and lifecycle vectors |
| Independent interoperability | Not established | WBH-C04 independent consumer against exact archives |
| Profile conformance | Not established; draft-derived mappings are package behavior | Revision-pinned WoT Profile assertion corpus |
| External certification | None | External certification artifact; no internal gate substitutes for it |

## Remaining-claim ledger

| ID | Unsupported/unproven claim | Disposition |
|---|---|---|
| WBH-R01 | Exactly-once remote close / reconnect durability | Consumer session contract; WBH-C02 documents failure cells |
| WBH-R02 | Bounded total memory or stream mailbox | WBH-C03 allocation/overload proof; byte limits alone insufficient |
| WBH-R03 | SSRF protection or safe cross-origin credential forwarding | Consumer destination/audience policy; syntax checks insufficient |
| WBH-R04 | All TD operations or non-JSON content | Outside nine-operation profile; new reviewed mapping required |
| WBH-R05 | Full WoT Profile/Registry/HTTP client conformance | Explicit nonclaim; no badge or label upgrade from test count |
| WBH-R06 | Whole declared runtime matrix and registry installation | WBH-C05 exact artifact/dependency evidence |
| WBH-R07 | Local tracker exclusion from archive | Inspect every candidate archive and reject any `docs/tasks/local/` member |

## Local evidence contract

Optional file: ignored `docs/tasks/local/wotex-binding-http-tracker.yaml`.
Schema is `schema_version: "1.0.0"`, `package`, `source_commit`,
`dependency_digests`, `items`.
Items keyed by WBH-C/WBH-R IDs carry `state`, `evidence`, `limitations`,
`next_action`; each evidence names gate, command, result and artifact digest.
No mutable status, worker assignment, attempts or approvals enter tracked
specifications/plans or package output. Unknown is not passed.

Package inputs allowlist publishable documentation and structurally exclude
`docs/tasks/local/`. Every candidate archive still proves the exclusion; Git
ignore alone never counts. A clean checkout requires no local tracker or
external automation service to build, test or select a normative task.
