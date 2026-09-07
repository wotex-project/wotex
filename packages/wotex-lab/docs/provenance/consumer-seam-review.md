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
dependency locks and ownership documents. Run `ruby bin/check-source-cohort`
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
