# BLE/GATT physical lab

Protocol contract: `wotex-ble` and `wotex-runtime`.

Runbook status: ready to prepare. No physical result is claimed.

## Initial hardware

- Raspberry Pi 3 Model B v1.2 running Linux and BlueZ.
- Arduino Nano 33 IoT as the controlled GATT peer.
- An independently manufactured BLE sensor for a later interoperability run.

## First fixture

Nano #1 exposes:

- read-only `motion` Property;
- notifications for motion changes;
- optional `identify` acknowledged write;
- explicit protocol revision.

Start with the onboard IMU. Add the confirmed PIR input only after electrical
verification.

## Acceptance

- [ ] Linux and BlueZ see the adapter and peer.
- [ ] The `wotex-ble` physical hardware lane reads one characteristic.
- [ ] The persistent backend discovers the expected service and characteristics.
- [ ] A read returns the expected value.
- [ ] A subscription delivers distinct updates.
- [ ] An acknowledged write performs only the fixture-safe Action.
- [ ] Peer disconnect is typed and cleanup remains bounded.
- [ ] Borrowed and owned connection semantics are tested.
- [ ] Private or random address changes do not redefine durable Thing identity.
- [ ] A malformed value is rejected without corrupting later reads.

## Evidence

Record the adapter identity, BlueZ version, Nano firmware commit, GATT UUID set,
exact `wotex-ble` native manifest, WoTEx commit and raw-value digests.
