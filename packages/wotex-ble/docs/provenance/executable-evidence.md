# Executable evidence

Evidence collected 2026-09-08 using Elixir 1.20.2 / OTP 29.0.4.
Development contract supports Elixir 1.18+; the lower-version matrix has not been
executed in this workspace. Use CI before graduation. No consumer parity or
certification is inferred from unit coverage.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The reviewed Decimal advisory metadata exception and regression are documented
in SECURITY.md and the dependency-security test.

## Interoperability

NOT RUN: Linux BlueZ and a connected Battery Service device were not supplied.
The default suite exercises the executable boundary with an explicitly named
fixture command; it does not count as Bluetooth device interoperability.
On a Linux host with a connected device and known Battery Level object path:

```sh
WOTEX_PATH_DEPS=1 WOTEX_BLE_BUSCTL=/usr/bin/busctl \
WOTEX_BLE_CHARACTERISTIC_PATH=/org/bluez/hci0/dev_00_11_22_33_44_55/service0001/char0002 \
mix test --include hardware test/interop/bluez_device_test.exs
```

Replace the object path with the actual selected characteristic. The optional
suite fails on absent executable, missing service, no response or invalid value.
Discovery, pairing and notification lifecycle remain separate gates.

Container source commits are pinned. Base-image/package-manager inputs may move;
these are reproducible source fixtures, not claims of bit-identical image builds.
Interoperability tags are excluded by default. Explicit invocation requires the
configured peer and must fail if that peer or expected response is missing.

## Evidence identities

The hashes identify reviewed test sources, not an immutable release or a promise
that all future test executions will pass. The mandatory gate and optional peer
commands above must be rerun after relevant changes.

| Test source | SHA-256 |
| --- | --- |
| `test/interop/bluez_device_test.exs` | `bd7a5e444ec053c87c84de6d387305f365a4c5830afd3cf1298c86571bc1849a` |
| `test/wotex/ble/bluez_test.exs` | `8fe5771f925c7e6955561e32ac9a5cac2204e64c5671dd6e5d479148adf237a8` |
| `test/wotex/ble/mapping_test.exs` | `7a5dd81cc91455621cf0b19fb81448e8ee52cd51c4949e541a46c2a0b361e7ec` |
| `test/wotex/ble/port_test.exs` | `5e01b43e5db1a5cdb6ee0dc894c694b1a8fbe9a64ce86243c45014fba8ae9e59` |
