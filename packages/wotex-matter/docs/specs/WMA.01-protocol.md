# WMA.01 Matter protocol and graduation contract

Matter 1.6 was announced by CSA on 2026-06-17. The connectedhomeip reference
SDK v1.6.0.0 (2026-08-20), commit 250a9e6c50ee2068107f3c4808b680f5f2925415,
is the executable reference. The complete Matter 1.6 Core text was not accessible
in this research; distinguish SDK-derived requirements from unreviewed normative
clauses. No certification, complete stack or commissioning claim is implied.

Typed interaction paths separate fabric, operational node, endpoint, cluster,
and attribute/command/event. IDs have distinct widths and reserved ranges;
explicit read wildcards are excluded from concrete writes/invokes. Fabric
identity is mandatory at an operational boundary and must not be lost in a
consumer-neutral map. Bridge endpoint metadata does not grant fabric authority.

TLV retains signed/unsigned widths, Boolean, finite float, UTF-8 string,
byte string, null, structure, array, list and end markers. Preserve unknown
tags, distinguish absent from null, reject incomplete lengths, invalid UTF-8,
unbalanced containers, integer overflow, excess depth and aggregate allocation.
An Elixir TLV codec is not a replacement for CASE/PASE or the Interaction Model.

A real controller port owns the pinned SDK, credentials, sessions, subscriptions,
commissioning windows and fabric storage. Caller-started processes require
explicit cleanup and subscriber monitoring. Secure commissioning must reject
failed attestation; never enable bypass flags. PASE privilege is not operational
ACL authority. Read/write/invoke/subscription results retain per-path status and
partial failures. Timed interactions, data versions and subscription intervals
must be passed explicitly; timeout does not prove a write had no effect.

CHIP Tool is an interoperability/development controller. Interactive mode keeps
sessions and subscriptions; one-shot output is not a stable machine protocol
without a pinned parser. Prefer a versioned structured controller port. Standard
SDK test harness and CHIP Tool have separate fabric stores. Never mix them.

WoT mapping is a documented Wotex profile: attributes to Properties, commands
to Actions and supported events to Events. Forms retain protocol path metadata
and extension terms. Do not claim an invented URI scheme is a W3C standard.

Acceptance: path and TLV properties/malformed cases, fake-port contract tests,
real SDK example peers, denied ACL, attestation failure, expired window, session
restart, lost subscriptions and unsupported paths. SDK tests alone do not
establish CSA certification. Simulator scenarios remain explicitly test-only.

## Common library rules

Use structured credential-free Error values, explicit finite budgets, immutable
address/value maps, no Application callback and no implicit runtime selection.
Compatibility callbacks are capabilities/connect/send/receive/disconnect/health_check/
subscribe/unsubscribe. A consumer port failure, malformed return or missing
transport is an error; never select simulation. Telemetry event prefixes are
[:wotex, :matter, ...] with bounded non-secret measurements. Consumer migration
requires differential scenarios against both implementations before replacement.
