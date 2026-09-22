# Cross-protocol QA scenarios

These product-neutral scenarios test WoTEx against IoT failure modes and fleet
behaviour without coupling the public lab to a private platform.

## Device onboarding

- unknown first packet arrives before enrollment;
- identity becomes known only after deterministic evidence;
- one physical device reports multiple channels;
- device profile or firmware revision changes;
- duplicate enrollment attempt;
- gateway and end-device identifiers remain distinct.

## Transport and delivery

- duplicate uplink;
- out-of-order uplink;
- stale retained state;
- reconnect after broker or gateway loss;
- intermittent gateway;
- delayed Event after host restart;
- oversized or malformed payload;
- unsupported protocol revision;
- authentication failure;
- transport accepted but physical effect unconfirmed.

## Data semantics

- temperature and humidity from one physical unit remain distinct affordances;
- unit conversion never changes canonical evidence;
- zero is not missing;
- invalid or nonfinite values are rejected or marked;
- source timestamp and receiver time remain distinguishable;
- signal metadata is preserved without leaking into Property values.

## Fleet state

- gateway online and offline transitions;
- sensor low-battery state;
- weak-signal degradation;
- silent device or overdue heartbeat;
- device returns with a new transient address or session;
- one device appears through multiple gateways;
- one semantic sensor arrives through different transports.

## Alerts and events

- repeated threshold crossing does not create uncontrolled duplicates;
- recovery Event follows degradation;
- replayed telemetry does not fire a current alarm;
- alert acknowledgement remains separate from device state;
- local rule evaluation works without AI.

## Headless consumers

The same admitted Thing must be consumable through:

- the Elixir API;
- an HTTP/JSON client where available;
- the CLI or Workbench;
- an independent non-Elixir consumer.

Consumers must not need vendor-specific protocol details after WoT
materialization.
