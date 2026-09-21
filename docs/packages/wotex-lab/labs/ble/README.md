# BLE / GATT physical lab

**Owner:** `wotex-ble` + `wotex-runtime`

## Initial hardware

- Raspberry Pi 3 Model B v1.2 running Linux/BlueZ.
- Arduino Nano 33 IoT as controlled GATT peer.
- Later: an independently manufactured BLE sensor for interoperability.

## First fixture

Nano #1 exposes:
- read-only `motion`;
- notification stream for motion;
- optional `identify` acknowledged write;
- explicit protocol revision.

Start with the onboard IMU, then add the confirmed PIR input after electrical verification.

## Acceptance

- [ ] Pi/BlueZ sees adapter and peer.
- [ ] `wotex-ble` physical hardware lane reads one characteristic.
- [ ] persistent backend discovers the expected service/characteristics.
- [ ] read returns expected value.
- [ ] subscription delivers distinct updates.
- [ ] acknowledged write performs only the fixture-safe action.
- [ ] peer disconnect is typed and cleanup is bounded.
- [ ] borrowed versus owned connection semantics are tested.
- [ ] private/random address change does not silently redefine durable Thing identity.
- [ ] malformed value is rejected without corrupting later reads.

## Evidence

Record adapter identity, BlueZ version, Nano firmware commit, GATT UUID set, exact `wotex-ble` native manifest, WoTEx commit and raw value digests.
