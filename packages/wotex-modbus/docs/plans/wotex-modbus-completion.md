# Wotex Modbus completion contract

Graduate this library independently. Acceptance requires typed values and
conversion, exact-revision protocol rules, Form mapping with extension
preservation, structured errors, explicit OTP ownership and cleanup, neutral
telemetry, unit/property/malformed-frame/lifecycle tests and an independent
protocol peer or hardware interoperability lane.

A compatibility adapter exposes `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
Wire acknowledgements never establish application truth. Unsupported operations
return an explicit error or the documented optional `:not_supported` sentinel.

The consumer keeps its implementation until differential scenarios and real
interoperability prove the supported scope. Consumer changes, deployment and
publication are outside this repository. Do not import consumer history or
metadata into this neutral history.

## Evidence rules

Every advertised behavior must name executable tests and exact standard
revisions. Negative responses and timeouts fail interoperability assertions.
Hardware tests require explicit target configuration; default tests never
contact a physical target. A simulator is useful evidence for contracts only.
Mutable audit notes remain in ignored `docs/tasks/local/`; this document is a
durable acceptance contract, not a progress tracker.
