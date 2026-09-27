# Exposed bridge software profile candidate

This is the finite WMA.09 implementation target. The
[catalogue](../specs/catalogue.yaml) records what has actually been built and
tested. No server or certification claim follows from these pins.

## Source and data model

- `connectedhomeip` v1.6.0.0, commit
  `250a9e6c50ee2068107f3c4808b680f5f2925415`, already pinned by the
  Matter software-source manifest. The server build must use this same exact
  source, generated data and dependency digests, with an independent build
  identity from the controller host.
- Matter 1.6 Core, Application Clusters and Device Type Library are the
  selected specification revisions. The SDK source's `data_model/1.6` XML is
  the machine-readable test baseline; generated ZAP data and build options
  still require a server-specific artifact receipt.
- Endpoint 0: Root Node `0x0016` revision 4. Endpoint 1: Aggregator `0x000E`
  revision 2. Endpoint 2 is reserved for the SDK's generated static dummy
  data, disabled at runtime. Bridged endpoints begin at 3 and cannot reuse a
  removed endpoint ID.
- Bridged Node `0x0013` revision 3 plus On/Off Light `0x0100` revision 3 or
  Temperature Sensor `0x0302` revision 3 form the initial non-Matter device
  cohort. A bridged endpoint must declare its actual device type; the bridge
  must not represent the underlying device as Matter-certified.

## Finite interaction set

| Device | Cluster and revision | Admitted operations |
| --- | --- | --- |
| Every bridged endpoint | Descriptor `0x001D` r3; Bridged Device Basic Information `0x0039` r6 | Read device/parts lists, identity and reachable; report consumer-approved reachable changes. |
| On/Off Light | On/Off `0x0006` r6 | Read/report OnOff; Off, On and Toggle commands after fabric ACL and consumer authorization. |
| Temperature Sensor | Temperature Measurement `0x0402` r6 | Read/report MeasuredValue with explicit unavailable/null handling. |

No other Device Types, clusters, writes, scenes, groups, binding, OTA or
long-running action completion are admitted by this candidate profile.
Commands return an accepted/denied/unknown outcome consistent with the
selected Matter command semantics; an accepted command does not assert a
physical effect. Reports are emitted only from consumer-approved observations.

## Release evidence still required

Pin the generated ZAP artifact, server build flags, test credentials and
independent controller peer before server coding is accepted. Then execute
commissioning, ACL and consumer authorization negatives, two device types,
restart/tombstone recovery, remove/re-add, report flow, timeouts, native loss,
store failure, sanitizer and exact-archive tests. Credentials in fixtures are
for tests only and must not ship in the Hex archive or a production binary.

Sources: [CSA Matter specification downloads](https://csa-iot.org/developer-resource/specifications-download-request/),
[pinned SDK release](https://github.com/project-chip/connectedhomeip/releases/tag/v1.6.0.0),
and the [SDK bridge example](https://github.com/project-chip/connectedhomeip/blob/v1.6.0.0/examples/bridge-app/linux/README.md).
