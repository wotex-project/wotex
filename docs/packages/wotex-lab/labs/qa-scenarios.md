# Cross-protocol QA scenarios

These scenarios are intentionally product-neutral. They exist to test WoTEx against realistic IoT failure modes and fleet behaviour without coupling the public lab to any private platform.

## Device onboarding

- unknown first packet arrives before enrollment;
- identity becomes known only after deterministic evidence;
- same physical device reports multiple channels;
- device profile/firmware revision changes;
- duplicate enrollment attempt;
- gateway and end-device identifiers are not conflated.

## Transport and delivery

- duplicate uplink;
- out-of-order uplink;
- stale retained state;
- reconnect after broker/gateway loss;
- intermittent gateway;
- delayed event after host restart;
- oversized/malformed payload;
- unsupported protocol revision;
- authentication failure;
- transport accepted but physical effect unconfirmed.

## Data semantics

- temperature and humidity from one physical unit remain distinct affordances;
- unit conversion never changes canonical evidence;
- zero is not missing;
- invalid/nonfinite values are rejected or marked;
- timestamp source and receiver time remain distinguishable;
- signal metadata is preserved without leaking into Property values.

## Fleet state

- gateway online/offline transitions;
- sensor low-battery state;
- weak-signal degradation;
- silent device/heartbeat overdue;
- device comes back with a new transient address/session;
- one device appears through multiple gateways;
- one semantic sensor arrives through different transports.

## Alerts/events

- repeated threshold crossing does not generate uncontrolled duplicates;
- recovery event follows degradation;
- old replayed telemetry does not fire a current alarm;
- acknowledgement of an alert is separate from device state;
- local rule truth works without AI.

## Headless consumers

The same admitted Thing must be consumable by:
- Elixir API;
- HTTP/JSON client where available;
- CLI/workbench;
- an independent non-Elixir consumer.

No consumer may need vendor-specific protocol details after WoT materialisation.
