# WBL.08 — Explicit write modes and native host parity

Version: 0.1.0. Updated: 2026-10-13. Status: accepted target.
Implementation: planned. Evidence: missing. WBL.01–07 remain unchanged.

## Scope and operations

This additive generic GATT contract covers explicit write modes and a separately
selected CoreBluetooth host. Vendor commands and consumer authority stay outside
this package. Existing acknowledged BlueZ operations keep their current default.

**WBL08-01.** The successor write operation selects `:with_response` or
`:without_response`. Unknown/duplicate mode rejects; a missing mode preserves
the existing acknowledged default. Validate characteristic identity/generation,
supported property, payload/MTU bounds, security, link and one original deadline
before queueing. An unsupported backend/mode refuses without fallback.

With-response results attribute an actual ATT response/error. Without-response
results distinguish native queue acceptance, refusal and delivery uncertainty;
they never fabricate an ATT acknowledgement or physical completion. Independent
read/report evidence is a separate consumer decision. Native IPC and Runtime
mapping retain mode, original request and evidence class end to end.

**WBL08-02.** Readiness/backpressure and queue bounds share the original
deadline. Pre-acceptance cancellation/disconnect prevents new unsent work;
post-acceptance loss retains uncertainty without replay or mode substitution.
Late callbacks cannot settle a successor connection/request generation.

## Host and lifecycle

**WBL08-03.** Select BlueZ or CoreBluetooth explicitly through public
consumer-supplied configuration. Loading the package starts no host, permission
prompt or discovery. The consumer supervises permission, pairing/security,
discovery, writes, subscriptions, cancellation and retirement. A macOS backend
does not require Linux dependencies merely to load it.

Native peripheral identifiers are private host-route identities, not portable
device IDs or authentication. Validate service/characteristic association for
the current host/link generation. Unsupported security/pairing/long-write cells
reject under an explicit backend capability matrix.

**WBL08-04.** Sleep, permission denial/revocation, adapter reset and link loss
close pending routes and report continuity loss. Reconnect supplies a new
generation/baseline, not a synthetic event or fresh restored value. Finite receive
credits/queues stop on owner death. Retirement requires actual owned native
resource cleanup; OTP timeout alone is insufficient. Private identities and
credentials never enter public errors, telemetry or portable profiles.

## Compatibility, entry and acceptance

Before code freeze public option/result/error and IPC revisions, the exact
BlueZ/CoreBluetooth capability matrix and independent vectors. Old IPC peers
reject new formats rather than ignoring mode. Historic BlueZ software evidence
does not qualify macOS permissions or physical GATT/RF operation.

| Case | Requirements | Expected observation / falsifier |
| --- | --- | --- |
| WBL08-T1 | 01 | Independent response/command peers observe the selected mode; command acceptance supplies no fabricated ACK |
| WBL08-T2 | 01–02 | Wrong property/MTU/mode/route, deadline, saturation and pre-send cancellation send nothing |
| WBL08-T3 | 02, 04 | Post-accept loss, late callback and reconnect preserve uncertainty; no resend or stale settlement |
| WBL08-T4 | 03–04 | Installed Mac permission/sleep/readiness/notification/owner-death/retirement corpus passes; existing Linux corpus is preserved |
| WBL08-T5 | 01–04 | Independent Runtime/archive peers retain mode/evidence and reject incompatible IPC without consumer-specific mappings |

WBL.02 owns the protocol baseline. The [Apple write-mode interface](https://developer.apple.com/documentation/corebluetooth/cbcharacteristicwritetype)
supplies native API vocabulary, not actuator qualification.
