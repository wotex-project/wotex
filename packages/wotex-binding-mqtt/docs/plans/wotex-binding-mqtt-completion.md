# Wotex MQTT binding completion contract

Plan `WBM-C@1.0.0`; package baseline `wotex_binding_mqtt 0.1.0`. This tracked
document fixes durable work scope, prerequisites and acceptance, not mutable
approval. Catalogue `docs/specs/catalogue.yaml` assigns WBM.01–03 identities,
versions and evidence. Changes are reviewed revisions, not retroactive changes
to historical evidence.

## Ownership and compatibility

Wotex owns TD terminology/values, Runtime owns interaction selection and
explicit subscription supervision, and this binding owns MQTT values, mapping
and JSON adaptation. The consumer supplies client sessions, credentials,
supervision, broker policy, canonical Thing state, durability and recovery.
Do not add a client, Application callback, connection manager, process, Repo,
framework, scheduler or global handle registry.

Package dependencies declare `wotex ~> 0.1.0`, `wotex_runtime ~> 0.1.0`, Jason
and Elixir `~> 1.18`. Local path proof is distinct from the declared registry
graph; record exact direct/transitive inputs. Tested OTP, Elixir and broker
capabilities must be named explicitly. MQTT 5 shared-topic grammar does not
prove all clients negotiate that feature. Changing value fields, notification
envelope, callbacks, mapping/defaults or errors needs compatibility vectors.

## Stable work packages

| ID | Prerequisites | Deliverable | Acceptance |
|---|---|---|---|
| WBM-C01 | WBM.01–03 and declared TD/Runtime interfaces | Standards/operation inventory | Seven mapping rows, unsupported cells and exact vocabulary/defaults bind positive/negative tests |
| WBM-C02 | WBM-C01 | Client lifecycle/recovery proof | Retained timeout, exception/invalid return, open/close failures, concurrent handles and stop/restart covered; session ownership external |
| WBM-C03 | WBM-C01 | Limits/security closure | Payload/topic/filter thresholds, allocation/cardinality, sustained delivery/receiver overload, secret capture and client authority tested or explicitly delegated |
| WBM-C04 | WBM-C02, WBM-C03 | Exact archive/reference consumer | Rebuild declared artifacts without live source; supplied client exercised through actual Runtime supervisor and paired Forms |
| WBM-C05 | WBM-C04 | Public release candidate | Package contents, docs, metadata/license/security, dependency installation and claims pass all applicable gates |
| WBM-C06 | WBM-C05 | Stable API decision | Public values/errors/defaults and draft-sensitive choices frozen with compatibility evidence and migration decisions |

## Five evidence gates

Each evidence record identifies source/archive digest, direct/transitive
dependency inputs, command, configuration, vector set, result and limitations.
No gate authorizes an automated push, tag, package or release publication.

| Gate | Required evidence | Nonclaim |
|---|---|---|
| `repository_green` | `WOTEX_PATH_DEPS=1 mix check --no-retry`, coverage at least 95%, strict static checks, docs without warnings, passive-loading/boundary tests | Not registry install or protocol certification |
| `archive_consumer_green` | Build without path switch; a separate minimal Mix consumer installs exact archives and exercises one mapping/transport success plus typed rejection through public API, with no live source | Not complete Runtime lifecycle |
| `reference_consumer_green` | WBM-C04 semantic and failure vectors, real supervision and explicit client ownership | Not actual broker fleet interoperability |
| `public_release_candidate` | Prior gates; clean package/metadata/license/security/dependency/standards evidence, no mutable local notes | Not publication permission |
| `stable_api_candidate` | WBM-C06 matrix; all supported cells/bounds/recovery claims proven | Not universal WoT/MQTT conformance |

Existing package/archive/application-free commands are supporting checks, not
replacement for independent consumer tests. Report any skipped or unavailable
mandatory check; zero skipped tests does not prove a missing test exists.

## Standards-claim matrix

| Claim | Exact repository baseline | Evidence under `test/wotex/binding/mqtt/` | Limitation |
|---|---|---|---|
| Topic Name/Filter and QoS values | OASIS MQTT 5.0 2019-03-07; 3.1.1 2014-10-29 | `topic_test.exs`, `qos_test.exs`, `command_test.exs` | No session/wire/QoS delivery guarantee |
| MQTT Form vocabulary/defaults | WoT MQTT Binding Editor's Draft 2026-07-01, observed 2026-09-02 | `mapping_test.exs` | Seven-operation subset, draft-sensitive |
| Retained Property-read rule | Same MQTT binding draft | `transport_test.exs` | Client timeout/retained authority required |
| JSON/byte boundaries | RFC 8259 and WBM.01 package limits | `json_test.exs`, `delivery_test.exs` | Not streaming or whole-process allocation bound |
| Binding Registry status | Draft Registry 2025-11-04 repository baseline | Provenance document only | No registration or W3C endorsement |

Primary links and dated observations live in `docs/provenance/`. They are not a
fresh revalidation of the present editor draft. Broader claims require exact
assertions and revision-specific positive/negative vectors; test counts and
funding or product plans are not standards evidence.

| Claim dimension | Current status | Promotion evidence |
|---|---|---|
| Value support | Topic, QoS, command, delivery and configuration values have named repository evidence | WBM-C01/03 close every field, bound and invalid case |
| Operation support | Seven draft-sensitive mapping rows only | Positive/negative vectors for every supported and rejected cell |
| Independent interoperability | Not established | WBM-C04 reference consumer and named broker/client cohort |
| Profile conformance | Not established | Revision-pinned profile assertion corpus; mapping tests alone do not qualify |
| External certification | None | External certification artifact; no internal gate substitutes for it |

## Remaining-claim ledger

| ID | Unproven or unsupported claim | Closure / owner |
|---|---|---|
| WBM-R01 | Finite end-to-end network deadline/temporary read cleanup | WBM-C02 supplied-client evidence |
| WBM-R02 | Hard-bounded encoding/matching/mailbox allocation | WBM-C03 threshold and overload proof |
| WBM-R03 | Authenticated delivery, secure TLS/ACL and no credential retention by client | Consumer authority; WBM-C03 boundary tests cannot sandbox client code |
| WBM-R04 | Once-only remote close/session recovery | WBM-C02/04 and consumer session contract |
| WBM-R05 | Full MQTT client/QoS2 exactly-once physical effect | Explicit nonclaim; no wire/session engine in this package |
| WBM-R06 | Action query/cancel, aggregate operations, binary codecs | Out of declared profile; new contract required |
| WBM-R07 | Registry membership/full WoT conformance/current draft parity | Explicit nonclaim; revalidate exact sources before broader claims |
| WBM-R08 | Registry installation/full platform range | WBM-C05 exact artifact/environment evidence |
| WBM-R09 | Local notes excluded from distribution | Inspect every candidate archive and reject any `docs/tasks/local/` member |

## Local completion memory

Optional tracker path: ignored
`docs/tasks/local/wotex-binding-mqtt-tracker.yaml`. Schema:
`schema_version: "1.0.0"`, `package`, `source_commit`, `dependency_digests`, `items`.
Items keyed by WBM-C/WBM-R IDs contain `state`, `evidence`, `limitations`,
`next_action`; evidence names gate, command, result and artifact digest. Mutable
audit/attempt/assignment/approval information never belongs in tracked specs,
plans, package contents or generated docs. Unknown cannot be marked passed.

Package inputs allowlist publishable documentation and structurally exclude
`docs/tasks/local/`. Every candidate archive still proves the exclusion; ignore
rules alone never count. A clean checkout needs neither tracker nor external
automation service for local work.
