# Wotex Runtime completion contract

Plan `RT-C@1.0.0` governs package `wotex_runtime 0.1.0`. It defines durable
requirements, not mutable approval or progress. Requirement changes need review
and a plan revision; historical Git content remains immutable. The normative
catalogue is `docs/specs/catalogue.yaml`.

## Ownership and compatibility

Wotex owns Web of Things values and terminology; Runtime owns only the listed
ConsumedThing/ExposedThing mechanics. The consumer owns policy, canonical
Property/Action/Event truth, persistence, credentials, transports, deadlines,
supervision, overload, recovery and physical effects. No application callback,
database, framework, global registry, scheduler or transport implementation may
be introduced as a completion shortcut.

The Mix package declares `wotex ~> 0.1.0` and Elixir `~> 1.18`.
`WOTEX_PATH_DEPS=1` is local development proof, not proof that the declared
registry graph installs. Record exact core/source digests. Every Elixir/OTP
pair claimed needs explicit evidence; one machine does not prove the whole
dependency range. Package, specification and evidence versions are separate.

## Stable work packages

| ID | Prerequisites | Deliverable | Acceptance |
|---|---|---|---|
| RT-C01 | WRT.01–03, core value contracts | Exact operation/value/error/evidence inventory | Every public function and unsupported cell mapped to named tests |
| RT-C02 | RT-C01 | ConsumedThing/subscription hardening | Raised/exited/malformed callbacks, result identity mismatch, invalid receiver/options, receiver death, concurrent stop, restart, forced kill and cleanup failure tested |
| RT-C03 | RT-C01 | ExposedThing boundary proof | Inbound Form/policy/schema checks assigned to consumer; invalid routing invokes no handler; concurrent callbacks and exception propagation proven |
| RT-C04 | RT-C02, RT-C03 | Independent reference consumer | Exact archives; zero/one/multiple subscriptions, shutdown budgets, explicit ports and aggregate negative cells |
| RT-C05 | RT-C04 | Release evidence dossier | Package contents, dependency closure, docs, license/security and compatibility inputs are complete and internally consistent; gates evaluate the dossier separately |
| RT-C06 | RT-C05 | Stable API decision | Retained public fields/errors/defaults, compatibility vectors and migration notes; all claimed cells proven |

RT-C02 must specify bounds before implementation: request/metadata cardinality,
Form/profile selection cost, callback budgets, mailbox overload and receiver
behavior. Each bound needs threshold/over-threshold tests and allocation
evidence. Consumer-owned limits must not be relabelled package guarantees.

## Five evidence gates

Each gate records exact source/dependency tree or archive digest, command,
configuration, vector identities, result and limitations. No gate requires an
automated push, tag, release or registry publication.

| Gate | Required evidence | Does not establish |
|---|---|---|
| `repository_green` | `WOTEX_PATH_DEPS=1 mix check --no-retry`: formatter, strict Credo, types/docs, coverage, boundary checks; report skipped/unavailable tools | Default registry install or integration |
| `archive_consumer_green` | Build without path overrides; a separate minimal Mix consumer installs the exact archive/dependency artifacts and exercises one supported success plus typed error through public API, with no live source | Full lifecycle behavior |
| `reference_consumer_green` | RT-C04 tests against that archive, explicit ports and real supervision | External protocol certification or production acceptance |
| `public_release_candidate` | Prior gates, metadata/license/security, docs links, dependency installation and standards audit; no tracker/secret in archive | Publication permission or stable API |
| `stable_api_candidate` | RT-C06 compatibility matrix; supported-cell ambiguity closed; advertised bounds/recovery evidenced | Compatibility forever or universal WoT conformance |

Existing `bin/check-package` compiles unpacked source against prebuilt core
BEAMs; it does not alone prove independent dependency installation or complete
reference-consumer semantics. No new hook/script substitutes for ExUnit.

## Standards-claim matrix

| Claim | Exact authority | Executable evidence | Boundary |
|---|---|---|---|
| Named operations and Form mechanics | TD 1.1 Recommendation 2023-12-05 | `consumed_thing_test.exs`, `form_selector_test.exs` | Explicit profile/Form cells only |
| Nine Thing-level operations | Same TD, top-level Forms; WRT.03 | ConsumedThing/ExposedThing/FormSelector tests | Binding support separate |
| Consumer-owned subscription lifecycle | WRT.01 | `subscription_test.exs` | No durability, bounded mailbox or guaranteed remote cleanup |
| ExposedThing dispatch | WRT.02 | `exposed_thing_test.exs` | No selected inbound Form or policy authority |
| WoT Scripting API | Note 2023-10-03 | No full conformance suite | Guidance only; no JavaScript API claim |

Tests above are under `test/wotex/runtime/`. Standards dates identify the
repository engineering baseline, not fresh revalidation of every source.
Broader claims need revision-specific assertions and positive/negative vectors.

| Claim dimension | Current status | Promotion evidence |
|---|---|---|
| Value support | Runtime request/result/context/error and subscription values are covered by named repository tests | RT-C01/02 close every public value and malformed boundary |
| Operation support | Only the exact WRT.01–03 operation cells are implemented | Positive/negative vectors per operation and admitted binding profile |
| Independent interoperability | Not established | RT-C04 reference consumer against the exact archive |
| Profile conformance | Not established | A separate revision-pinned profile assertion corpus |
| External certification | None | External certification artifact; no internal gate substitutes for it |

## Remaining-claim ledger

| ID | Unsupported or unproven claim | Required closure / owner |
|---|---|---|
| RT-R01 | Hard-bounded memory/mailbox/callback latency | RT-C02 and consumer overload contract |
| RT-R02 | Credential-safe handling of every exception/crash | RT-C02; consumer callback code remains trusted |
| RT-R03 | Request/result identity cannot be substituted | RT-C02 transport-return correlation matrix |
| RT-R04 | Full selected inbound Form/schema validation | RT-C03 consumer-server contract, not current route lookup |
| RT-R05 | Exactly-once delivery, remote cleanup or physical effect | Explicit nonclaim; consumer durable semantics |
| RT-R06 | Clean registry installation/full platform range | RT-C05 dependency and runtime compatibility proof |
| RT-R07 | Full Scripting API/WoT conformance | Out of declared scope; new contract required |
| RT-R08 | Local notes excluded from distribution | Inspect every candidate archive and reject any `docs/tasks/local/` member |

## Local completion memory

Optional mutable state belongs only at ignored
`docs/tasks/local/wotex-runtime-tracker.yaml`, never in Git, catalogue, plans,
specs, tests, package archives or ExDoc. Schema: `schema_version: "1.0.0"`, `package`,
`source_commit`, `dependency_digests`, and `items` keyed by RT-C/RT-R IDs with
`state`, `evidence`, `limitations`, `next_action`. Evidence records name gate,
command, result and artifact digest; unknown is not passed. No scheduler,
worker claims or cross-repository authority belongs here.

Package inputs allowlist publishable documentation and structurally exclude
`docs/tasks/local/`. Every candidate archive still proves the exclusion; Git
ignore alone never counts. No local tracker is needed to compile, test or
choose a normative task.
