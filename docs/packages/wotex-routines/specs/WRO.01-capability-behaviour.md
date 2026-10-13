# WRO.01 — Capability and behaviour basis

Version: 0.1.0. Updated: 2026-10-13. Status: accepted target; implementation planned.

## Scope and ownership

This prospective optional package defines consumer-neutral behaviour semantics
over installed WoT capabilities. Core retains TD/TM interpretation; Runtime
retains interaction planning; Continuum retains compatible exchange values.
The consumer owns instance identity, canonical observations, policy, credentials,
storage, clocks, supervision and effects. No new device-description parser,
global controller or mandatory runtime is introduced.

A capability is an installed typed interaction contract. A behaviour defines
its preconditions, transitions, effect domains and outcome evidence. A mapping
selects installed semantics. A concrete enrolled instance and its qualification
remain consumer decisions. All four identities remain distinct.

## Required basis

**WRO01-01.** Each installed behaviour basis supplies these immutable values:

| Area | Required semantics |
| --- | --- |
| Identity | Exact contract/version, byte and semantic identities, implementation/compiler basis |
| Interaction | TD/TM affordance reference, supported operation/input/output types and required security/lifecycle contract |
| Value | Dimension, exact unit/scale, valid domain, invalid/missing policy and conversion/error rules |
| Evidence | Accepted report source/quality, required freshness and source continuity, completion threshold |
| Effects | All touched resource domains, possible partial/unknown outcomes and repeat/stop/supersession rules |
| Timing | Deadline, duration/dwell/cooldown and supported uncertainty policy |
| Analysis | Model profile/property scope or explicit unsupported classification |

A required missing field/contract rejects admission. Optional annotations remain
inert. Data may narrow installed operations/ranges, never add privileged
semantics. No profile includes executable expressions, raw routes/bytes,
credentials, module names or automatic timers. Limits are explicit constructor
inputs and validated before allocation; no environment-derived registry exists.

**WRO01-02.** TD/TM affordances and Forms come from WTX.01/02/04. Behaviour fields
are package extensions, never W3C vocabulary. Required model/import closure is
immutable and supplied offline by the consumer; unknown/cyclic/missing closure
rejects without a network fetch. A Form or valid schema does not authenticate
an instance, select an implementation or authorize an operation.

**WRO01-03.** Reconcile observation/intent/result/evidence values against
WCT.01–03 before adding a wire kind. Retain source identity/epoch/sequence and
time/trust when available, consumer receipt epoch/time, declaration/profile
basis, replay/continuity classification, value/unit and derivation provenance.
Unrepresented required semantics reject a proposed adapter; never silently
drop them into a generic context string. Package and wire versions are separate.

Freshness of receipt is distinct from source age. Retained/replayed data cannot
renew source freshness or fabricate an event. Unknown, invalid, stale and usable
qualities remain distinguishable; unknown values never become zero/false.
Derived occupancy/presence retains contributors and expiry, not raw sensor truth.

**WRO01-04.** Exact integer/rational conversion rejects overflow, incompatible
dimensions and required inexact rounding. A separately installed error policy
may permit named approximation; portable data cannot choose one. Temperature,
fraction, illuminance, power, energy and time are distinct dimensions.
Battery voltage is not battery fraction. Counter resets/wrap bind a source
epoch. Device-specific validation stays below generic routine evaluation.

**WRO01-05.** Effect domains conservatively cover a complete resource until
independent evidence justifies narrower concurrency. Different properties
can touch the same actuator or packet. Requested state, local queue acceptance,
protocol response, correlated report and reported equality are different facts.
A report match does not prove physical cause. An absolute operation is not
automatically safe to repeat after uncertain delivery.

## Compatibility and acceptance

Existing WTX/WRT/WCT meanings, limits and codecs remain unchanged. Before code,
freeze a closed native/schema representation, public constructor/error contract,
field-by-field Continuum mapping and independent vectors. Unknown executable
semantics and malformed caller-built structs must return structured errors.
No arbitrary scripts or downloaded implementation are admitted by this basis.

| Case | Requirements | Expected observation / falsifier |
| --- | --- | --- |
| WRO01-T1 | 01–02 | Independent scalar, event, fast/slow actuator and media producers share capability semantics without vendor branches; missing required contracts reject |
| WRO01-T2 | 02–03 | Offline closure/Continuum conversion round trips retain every required identity/quality; unknown required semantics never become permissive defaults |
| WRO01-T3 | 03–04 | Stale/replayed/derived values, battery dimensions, invalid sentinel, overflow and counter reset stay distinct under independent vectors |
| WRO01-T4 | 05 | Coupled properties conflict; ACK alone never satisfies reported-match completion; uncertain absolute effect is not repeated |

These are planned software obligations. Installed-host and physical qualification
are separate consumer evidence. Standards vocabulary source:
[TD 1.1 Recommendation, 5 December 2023](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/).
