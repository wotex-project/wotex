# Wotex Lab completion contract

Plan version: 1.5.0. Package baseline: 0.1.0. Normative Lab owners:
[specification catalogue](../specs/catalogue.yaml).

This is a versioned implementation and acceptance baseline, not an execution
tracker. All work packages below belong to the accepted programme. Dependencies
express what evidence must exist before a claim can be accepted; they do not
defer or waive obligations. The requested package foundation implements a
bounded subset without claiming the programme is complete. Changing an accepted
obligation requires a new plan version and compatibility explanation.

Version 1.1 adds concrete metrics/AI and native-workbench obligations (C12/C13),
including foundation design tokens, and strengthens transport/security seam
evidence. Existing package APIs and accepted WoT semantics do not change.
Reference host dependencies stay optional for library consumers. Sibling fixes
are package-owned changes; this contract does not promote their readiness.

Version 1.2 selects optional Explorer analysis and interactive chart lifecycle
acceptance under C03/C08/C10/C12/C13, following the
[interactive analytics decision](../decisions/0005-interactive-elixir-analytics.md).
It retains the independent numerical, dataframe and rendering layers, bounded
missing-aware previews, the passive first-tensor closure and every existing
acceptance gate. Archived packages and advisory conflicts are not waived.

Version 1.5 selects the PHA.02 shared design system and bounded Svelte islands
inside the LiveView Workbench. LiveView retains routes, authorization,
canonical state, evidence and effectful commands. The same production Svelte
components publish through static Storybook; HEEx fallbacks and a separate
Phoenix Storybook host cover no-JavaScript and real-transport behavior.

## Work packages

| ID | Prerequisites | Required deliverable | Acceptance |
| --- | --- | --- | --- |
| WLB-C01 | WLB.01 | Passive package, explicit isolated OTP instances, bounded role supervisors | Two live instances; malformed config, capacity, role crash, shutdown; public docs/types and package checks |
| WLB-C02 | WLB-C01; WLB.02 | Closed scenario data, explicit component activation, bounded runner and replay | Unknown capability rejected before startup; identical frontend inputs; concurrent runs, cancellation, late result, partial-start rollback, callback failure, cleanup |
| WLB-C03 | WLB.03; WNX.01 | Nx adoption suite, explicit converter/backend, windows, Serving, Axon training, evaluation and proposal policy | Every WLB.03 lane; deterministic fixtures, mask/quality/provenance, split leakage checks, backend tolerance, failure means no effect |
| WLB-C04 | WLB-C02; WRT.01–03; WBH.01–03; WBM.01–03 | Loopback, NoSec/StaticRef, Req/SSE, EMQTT/broker and exposed Things | Real transport positive/negative cells, fresh-credential reconnect, receiver/handle isolation, bounds and cleanup; WLB.04 complete |
| WLB-C05 | WLB-C02; WTD.01; WCT.01–03 | Independent ETS/SQLite stores, explicit directory ports and Continuum channel | Both stores pass same contract suite via different algorithms; all public operations, concurrent conflict, expiry revision, interrupted transaction, envelope/compatibility/replay failures |
| WLB-C06 | WLB-C03–C05 | Canonical smart room and explicit decision/effect state | Discover/interact/observe/exchange/infer/decode/decide/dispatch; stale/duplicate/conflicting/revoked attempts cannot mutate state; WLB.05 complete |
| WLB-C07 | WLB-C02–C06; WCF.01 | Versioned evidence, independent target, telemetry, chaos and benchmarks | WLB.06 positive/negative outcomes, subprocess isolation, pinned artifacts, leak sentinels, calibrated performance cohorts |
| WLB-C08 | WLB-C02–C07; WLB-C09; WLB-C13 | All sixteen executable cookbooks and generated public graph/interfaces | WLB.07 rows run as notebooks and automated scenarios; IDs/callbacks/sources resolve; ownership retrieval corpus passes |
| WLB-C09 | WLB-C03; WLB-C06; WLB.09 | Explicit ex_maude profile, finite control model, bounded verification and counterexample replay | All formal-model cases, inconclusive vs exhaustion proof, no implicit binary install, two pools, timeout/crash/secret/injection tests; verification never dispatches |
| WLB-C10 | WLB-C07–C09; WLB.08 | Complete artifact builders, distribution checks and compatibility dossier | Archive/no-Git consumers, candidate Hex/Mix.install, OCI/npm/static/Nerves artifact checks, minimum/current and allowed-dependency cohorts, SBOM/license/security review; hosted and physical adoption use the qualification runbook |
| WLB-C11 | WLB-C10 | Explicit API compatibility report and readiness inputs | Every retained API/result/error/default and claim has evidence; incompatible changes have migration options; the maintainer's release or stable-API decision is qualification, not source implementation |
| WLB-C12 | WLB-C07; WLB.10 | PromEx metrics/panels, bounded ETS history, GreptimeDB bridge/query port and BeamLens skill | Protocol/store equality, retention, cardinality, loss/reset/clock cases, isolation, secret/prompt injection, cancellation and evidence-grounded AI queries |
| WLB-C13 | WLB-C03; WLB-C07; WLB-C12; WLB.11; PHA.02 | Neutral base theme and explicit Phoenix LiveView workbench with bounded Svelte islands | Shared tokens/components, typed island transport, HEEx fallbacks, bounded enhanced charts, static Storybook, real LiveView catalogue, dashboard exports, no-LLM flow, lifecycle/keyboard/theme/reconnect/security browser suite and clone-free host artifact |
| WLB-C14 | WLB-C08; WLB-C10; WLB-C13; WLB.12; DSH.01; PHA.01; PHA.02 | Unified built-in and static ecosystem documentation | All allowlisted packages and documentation sources emit isolated corpora; routes/links/search resolve; LiveView/static semantics and design-system digests match; docs and static Storybook compose collision-free; offline archive, browser/accessibility and fail-closed workflow-source vectors pass |

WLB-C01, descriptor/Nx example source and C13's base tokens form the foundation deliverable.
The catalogue records their status; prose or a source-only test cannot imply
C02–C14 completion. No placeholder module may claim to implement these items.

## Upstream closure map

Lab can expose failures and contribute independent consumer evidence. It cannot
declare another package's partial implementation finished. Native hardening,
exact schemas/errors, package release checks and API decisions stay in the
owning packages. The source index pins the inspected completion contract.

| Package | Lab evidence | Remaining owner obligations that still must be resolved |
| --- | --- | --- |
| wotex | C03/C08/C10 supply WTX-C03/C04 consumers/corpus | WTX-C01 requirement map; C02 malformed/native/resource/error behavior; C05 compatibility/release decision |
| Runtime | C02/C04/C06 supply RT-C02–C04 lifecycle/consumer cases | RT-C01 exact cell inventory; package-owned C02/C03 fixes; C05 release dossier; C06 API decision |
| HTTP | C04/C07/C10 supply WBH-C02–C04 lifecycle/security/artifact cases | WBH-C01 mappings; native C02/C03 fixes; C05/C06 release/stability |
| MQTT | C04/C07/C10 supply WBM-C02–C04 lifecycle/bounds/artifact cases | WBM-C01 seven-operation inventory; native C02/C03 fixes; C05/C06 release/stability |
| Directory | C05/C10 supply WTD-C01–C04 dual adapters/concurrency/archives | Reusable port suite accepted by Directory; C05 claim/cohort review; C06 archive hygiene |
| Continuum | C05/C06/C10 supply WCT-C04 consumer | WCT-C01 all kinds; C02 UTF-8/native/codec limits; C03 schema/constructor agreement; C05 supply chain |
| Conformance | C07/C10 supply WCF-C03/C04 external target and isolation | WCF-C01/C02 assertion/corpus work; C05 explicit Discovery exclusion decision; C06 runtime discrepancy/compatibility; C07 archive hygiene |
| Nx | C03/C06/C10 supply WNX-C03/C04 explicit units/backend consumer | WNX-C01 forged/error matrix; C02 integer/overflow/ties; C05 backend/runtime cohort; C06 archive hygiene |

In the final programme every referenced upstream obligation needs a package-owned
accepted evidence link or its already permitted explicit non-claim. Lab test
success alone is insufficient. For a newly found package defect, reproduce it
through public APIs, attach the exact source/artifact/input and failing outcome,
and route the fix to that spec owner. No private API shim or silent capability
reduction can conceal it. Authorized sibling repairs follow each owning
package's spec, regression-test and verification workflow.

## Independent acceptance

The gates in WLB.08 are independent: foundation, package contents, base archive
consumer, full-host Workbench archive, reference consumer, documentation
distribution, general distribution, public candidate, stable API.
Record exact commands, source tree/lock/artifact/schema/model digests,
toolchains, resource envelope and claim dimensions. The source gates determine
implementation status. Hosted adoption, publication, physical hardware and
maintainer release/API decisions follow the
[qualification runbook](qualification.md). Missing external prerequisites do
not permit a fake pass, visibility change, publication, or a weaker clone-free
definition.

No local tracker, coordinator state, worker attempt or consumer filesystem path
belongs in a published package. Package allowlists exclude the root `docs/tasks/local/wotex-lab/`.
Unpublished source results are labeled source results. Hosted mutations are
disposable and explicit; physical device authorization is outside the baseline.

## Explicit exclusions

The complete Lab is not a WoT framework, production identity provider, universal
database adapter, second protocol implementation, model registry, unrestricted
agent execution platform, physical control safety certification or new W3C
profile. Discovery search/transport corpus expansion is excluded by the current
upstream completion baseline. Adapter extraction into separate packages is not
a deliverable: references remain here and replacement seams are documented.
These boundaries are final scope decisions, not deferred features.
