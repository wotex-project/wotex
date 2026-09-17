# Consumer seam review

Review date: 2026-09-07. Scope: all eight public WoTEx specification catalogues,
their 19 normative specifications and completion contracts, with focused code
inspection of JSON/codec admission, Runtime credentials/results/subscriptions,
HTTP URI/header/action-target mapping, MQTT topic/session boundaries, Directory
authorization/validation, Nx window/encoding/output and conformance evidence
isolation. This is a source review, not exhaustive formal verification, an
independent wire interoperability result or a claim of zero vulnerabilities.

The original immutable revisions remain in `source-index.json`. The separate
`source-cohort.json` identifies the reviewed working-tree content, including
repairs not present at those commits. It hashes sorted relative paths and file
SHA-256 values under an explicit allowlist of source, specs, tests, fixtures,
dependency locks and ownership documents. Run `elixir bin/check_source_cohort.exs`
from the workspace to detect changed inputs. No network, execution scheduler,
readiness promotion or automatic baseline rewrite occurs.

## Findings and ownership

| Owner | Finding / checked seam | Resolution or precise acceptance boundary |
| --- | --- | --- |
| Core WTX.03 | TD/TM validators consumed formatted tuple errors as maps, collapsing `/title` to `/`; array validation eagerly indexed the whole list before a tiny node budget | Use structured validator errors and lazy indexing. Public TD/TM regression tests check field paths and payload sentinels; a 100,000-element native-array test proves early work termination |
| Runtime WRT.01/WRT.02 | Request/operation result correlation is already checked; subscription receiver lifetime, mailbox bounds, restart policy and callback-failure cleanup remain explicit RT-C02/RT-C04 obligations | No duplicate runtime added to Lab. WLB.04 requires real supervisor/failure tests; a normal stop with a permanent child spec is not evidence of durable cancellation |
| HTTP WBH.01–03 | Framing/credential fields and invalid URI syntax are rejected; mapped ActionStatus destinations may differ from the selected Form | WLB.04 now requires actual-target audience and DNS/IP/redirect admission. URI syntax and a nosec demo cannot prove SSRF resistance or authenticated reconnect |
| MQTT WBM.01–03 | Topic validation handles `$` topic rules and shared filters; connection credentials, retained sample age, reconnect and receiver bounds are client responsibilities | WLB.04 makes fresh credential resolution, disabled implicit reconnect, diagnostics redaction, retained/reset identity, ACL/Will/session-expiry and power-loss evidence explicit. QoS is not exactly-once physical effect |
| Directory WTD.01 | Authorization precedes repository access; accepted core validation options are only positive resource limits, not `validate: false` | No bypass introduced. Independent ETS/SQLite atomicity, conflict/paging/expiry and interrupted-transaction evidence remains required by WLB.05 and WTD-C01/C02 |
| Continuum WCT.01 | Native nested JSON object keys bypassed UTF-8 checks although values were checked; malformed unknown keys could enter error paths | Reject invalid keys at the parent path before construction/encoding; test native/forged values, failure details, malformed byte families and Unicode canonical round trips. Wire schema is unchanged |
| Conformance WCF.01 | Canonical outcomes differ from informal scenario labels; CLAUDE declared a stale toolchain floor/CI version | Lab preserves `pass/fail/unsupported/not_run/infrastructure_error` and records timeout/malformed as reasons. Conformance's contributor contract now matches `mix.exs` and CI. Independent target/OS containment remain distinct evidence obligations |
| Nx WNX.01 | Latest selection filtered and sorted candidates again for every row despite an existing index | Stream eligible candidates into a linear minimum selection. Generated reference comparisons preserve selected identity, ties, reversed-input determinism, empty selections and age policy. No model/backend/effect authority changes |

Core's early-array-work reproducer consumed over 210,000 reductions before the
repair with a node budget of two; the checked-in regression requires fewer
than 10,000 on that same bounded-admission path. This is a work-bound test,
not a cross-machine latency benchmark. Nx's improvement is algorithmic; no
unmeasured speedup percentage is claimed.

The repaired core, Continuum and Nx packages retain their existing public
ownership. No foundational package imports Lab or adds a client, store, LLM or
UI dependency. No catalogue implementation status is promoted by these fixes.
The selected GreptimeDB/PromEx/BeamLens/UI stack is specified in WLB.10/WLB.11,
with separate artifact, protocol, lifecycle, privacy and accessibility gates.

## Verification scope

The source suites across all eight owners are exercised on Elixir 1.20.2 /
OTP 29.0.4. The source-changing core, Continuum and Nx packages also use their
full `mix check --no-retry` gates (compilation, lint, types/docs, coverage,
dependency audits and package/archive checks). Archive checks have their own
declared scope; they are not silently upgraded to Lab's stricter no-Git,
archive-only dependency-closure consumer gate.

Lab's foundation additionally tests tokens/CSS determinism and light/dark
text/focus contrast. Lab, core, Continuum, Nx and Conformance suites are exercised at
Elixir 1.18.4 / OTP 27.3.4.15 as well. Browser accessibility, real Req/SSE and
EMQTT sessions, durable metrics, BeamLens provider/cancellation, independent
conformance targets, released artifacts and Nerves hardware are not proved by
these source tests. The content guard is checked both for matching input and
an injected mismatched digest, which must fail. The accepted contracts remain
required, without a fake
green status or a “zero drift forever” assertion.

## Runtime and HTTP follow-up cohort

Review date: 2026-09-08. Runtime is reviewed through
`c9c336a61e6b3cd8a1cd00f3ed7b52fb74a40aa6`, HTTP through
`b9fd354cfd843daa3bdfab38c667234191e992a5`. The other six content cohorts are
unchanged. This supplements, rather than rewrites, the historical revision
snapshot above.

Runtime's WRT.01 is now 1.3.0 and WRT.02 is 1.1.0. Reviewed changes cover
fixed request/metadata/profile/Form limits, forged Result revalidation,
credential-safe exception telemetry, explicit subscription option validation,
receiver/client-loss cleanup and concurrent stop outcomes. Exposed callbacks
remain synchronous in independent caller processes; their errors and effects
remain consumer-owned. A reproduced retry defect accepted negative attempt
counts and ambiguous duplicate options and raised on non-boolean idempotence.
The owning repair closes the four-option vocabulary, requires positive attempt
counts and known operations, and returns `:stop` for malformed inputs. Its
20,250-cell decision matrix passes without introducing timers or port calls.
Telemetry clock readings are explicitly measurement-only, not deadline or
retry authority.

HTTP's WBH.03 is now 1.2.0. A returned SSE handle is closed best-effort even
when its handshake is not a Response value. Tests cover that failure, exact
event thresholds, cleanup callback failure modes, duplicate raw closes,
concurrent Runtime stops, receiver death and linked client failure. No hidden
client, reconnect loop or remote exactly-once cleanup guarantee is added.

Both owners have a dated, exact-Decimal-3.1.1 lock/checksum and parser-regression
guard for the contradictory advisory range described in their SECURITY files.
The reported exponent is rejected through parse/cast/new, with default
threshold vectors; the acknowledgement does not disable other advisories.
Full owner checks pass on Elixir 1.20.2 / OTP 29.0.4: Runtime 66 tests at 95.6%
coverage, HTTP 66 cases (including two properties) at 97.2%. HTTP's default
Gettext/Sobelow probes are inapplicable absent those dependencies; all declared
package tools run. Archive compilation retains each owner's narrower stated
scope, not independent archive-only dependency reconstruction.

Workspace `mix check` now requires the content guard. Reference suites check
it before and after execution and bind the cohort file into their own digest.
WLB.04/05 transport and store records also bind the cohort, matching WLB.06/09;
no missing archive becomes an admitted artifact. The guard's actual CLI is
tested against matching, changed, missing-owner and symlinked fixture trees,
including preservation of the previous record. Accepted release, hostile-worker,
complete reference-programme and hardware obligations remain open.

The renewed workspace gate passes all 17 tools (309 tests, 24 excluded,
95.3% coverage); the concurrently executed Workbench gate passes all 13 tools
(59 tests, 93.2% coverage, plus five chart lifecycle checks). The all-lanes
reference attempt `d303bc2972d64f99575a5d9015ac5dcf` correctly records failure:
332 of 333 tests passed, but the Greptime test expected two rows after rapid
captures that can share one millisecond. A separate local 100-pair capture
reproducer observed 75 equal timestamps. The retained failure is not waived;
timestamp ordering and receiver deduplication require the WLB.10 follow-up.

The WLB.10 v0.7.0 follow-up rejects new non-advancing captures, revalidates
snapshot structs and consumes rejected attempt numbers. Its receiver test
uses explicit fixture timestamps and separately proves last-row deduplication
for same-label/same-time direct writes. The original failed attempt remains
retained. With the fix, all 17 Lab and 13 Workbench checks pass, and reference
attempt `7b4bef25cec0018565a7962ed3f3b07a` passes 336 tests with no exclusions,
with broker, Greptime and Maude enabled and source guards matching before/after.
The record still excludes full reference/artifact and outer-runner-containment
acceptance; a successful request remains distinct from a durable row count.

## Complete owner quality-cohort renewal

Review date: 2026-09-08. The six remaining owners now carry the same exact
Decimal 3.1.1 metadata-conflict review and parser/lock regression guard. No
dependency version is changed, no subject dependency enters Conformance, and
no numerical backend, clock, transport or storage authority is added. Core's
completion baseline 1.1.0 explicitly replaces its obsolete invalid-limit
fallback description with the already implemented WTX.03 refusal/preflight
contract. Nx's WNX.01 v1.2.0 reconciles the old scan-based table with its actual
selection-work score; 108 budget-boundary combinations and the existing
exhaustive selection properties preserve behavior. Nx and Directory's dynamic
invalid-constructor vectors also pass test compilation with warnings as errors.

All eight owners run their own full quality gate against this source cohort:

| Owner revision | Cases | Coverage |
| --- | ---: | ---: |
| core `8be2f24c02d832b3bb40b610566896d3c51b7059` | 77, including one property | 100.0% |
| Runtime `c9c336a61e6b3cd8a1cd00f3ed7b52fb74a40aa6` | 66 | 95.6% |
| HTTP `b9fd354cfd843daa3bdfab38c667234191e992a5` | 66, including two properties | 97.2% |
| MQTT `56119aa684b0f53dfb40b03f3b49d9fd23b2f264` | 61 | 97.7% |
| Directory `15ac9a7949423f08c44b8ddd15ab682c3b5e6d20` | 79 | 95.7% |
| Continuum `2e3567d50aba14bde68c0bffa8782675750d1589` | 50, including one property | 96.5% |
| Conformance `df3a009d2bb66542f4ee5843a1e737a3010218de` | 68, including one doctest | 96.5% |
| Nx `7d18925312c22256e63e9bdfb780e9ec24845287` | 53, including four properties | 95.1% |

Conformance and Continuum compilation is renewed after cleaning their generated
development/test application builds. Directory also builds docs in the docs
environment. HTTP's default absent-package Gettext/Sobelow probes remain
inapplicable. Upstream development-dependency compiler warnings in archive
reconstruction are visible; these results do not claim a warning-free dependency
closure. Existing owner archive checks retain their documented narrower scope.
The reviewed content guard matches all eight owners; the historical source index
is unchanged. Renewed WLB.04/05/06/09 source records bind this cohort, not missing
published archives. During WLB.05 renewal, repeated in-VM cookbook evaluation
also emitted a module-redefinition warning; the passing suite does not establish
isolated cookbook compilation.

The renewed Lab root gate passes all 17 checks (311 cases, 25 optional-lane
exclusions, 95.3% coverage). The Workbench gate passes all 13 checks (59 cases,
93.2% coverage and five chart JavaScript checks). The separate reference attempt
`b9dee4382a138959c98e825eeed122e9` passes 336 cases without exclusions, with
broker, Greptime and Maude enabled and matching source guards before/after.
These are source-cohort results, not full artifact or runner-containment proof.

## Advisory-waiver removal renewal

Review date: 2026-09-08. Hex no longer associates `EEF-CVE-2026-32686` with
the locked Decimal 3.1.1 cohort. All eight source owners, Lab and Workbench
therefore remove that ignore entry instead of preserving a stale waiver. Each
owner still binds the exact lock tuple and exercises Decimal's finite parser
thresholds; all owner quality gates pass with the advisory unsuppressed. The
content cohort below is renewed to those clean trees. This does not waive a
future matching advisory or turn a parser regression into a general Decimal
safety claim.

## Final hardening cohort renewal

Review date: 2026-09-08. The current content cohort incorporates Runtime
`ba2706073ada`, Continuum `9fbaf3d6cd0c` and Conformance `dd53f8052a5b`.
Runtime now fails closed when selecting dependency source mode, Continuum
bounds iodata before flattening it, and Conformance makes acceptance authority
explicit in its completion plan. The other five owner digests are unchanged.
Lab head `e14e68f` is the pre-renewal consumer revision; its catalogue and
BeamLens session-binding changes do not promote any source, artifact or
external-evidence axis.

`elixir bin/check_source_cohort.exs` matches all eight recorded owners. The
WLB.04, WLB.05, WLB.06 and WLB.09 evidence-manifest tests pass after rebinding
their exact source trees; WLB.06 and WLB.09 include the current catalogue.
Contract and graph checks remain source validation only. Historical
`source-index.json` revisions, missing dependency archives, optional external
lanes and the WLB.06 hostile whole-tree isolation exclusion remain unchanged.
