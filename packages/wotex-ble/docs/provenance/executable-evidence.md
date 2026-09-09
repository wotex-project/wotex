# Executable evidence

Current implementation: typed domain APIs, persistent Python/dbus-next ownership,
Agent/procedure/stream behavior and Runtime integration. The committed documentation
cohort `60d1e3c` has a passing full local gate: 8 doctests, 16 properties and
146 tests, one hardware exclusion; 51 Python contract tests; 95.0% coverage.
The [virtual-controller evidence](virtual-controller.md) identifies 15 real BlueZ
cases with two software controllers. These exercise the Python adapter and a
shared BlueZ wire stack. They do not execute the accepted C++ .13 backend.
Public BEAM/Runtime virtual-peer acceptance, native credit-flow execution and
complete stress/package evidence remain required. Uncommitted fixture work is
not acceptance evidence.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Acceptance boundary

[WBL.13](../specs/WBL.13-native-backend.md) defines the required native binary,
Mix/ExUnit tasks, exact version lanes and credit/resource tests. Its corpus is
specified and unexecuted. A passing current gate, a listed test path or a source
hash cannot establish execution of that target. Each completed software run must
bind case, corpus, source, SDK/binary, toolchain and cleanup-result hashes.
The mandatory runtime matrix is Elixir 1.18.4/OTP 27.3.4.15 and Elixir
1.20.2/OTP 29.0.4. Only identified executed lanes count as passing evidence.

## Committed source identities

These hashes identify the committed implementation/test inputs reviewed here;
they are not release artifacts or a claim about every future run. Fixture WIP is
excluded. Native software results require their own immutable manifest.

| Source | SHA-256 |
| --- | --- |
| `test/wotex/ble/contract_fixture_test.exs` | `3730f210ddcfa19258ccbdafd2721d50beae5234f431b8e81560b894bed32a7d` |
| `test/wotex/ble/runtime_integration_test.exs` | `9c32f64eabf16aff5e4121e2508b801ca6efb92975a4614f3aaca6ec6bbed470` |
| `test/wotex/ble/dbus_bridge_test.exs` | `7caf2b7d067ba761eeadc0d2b8886b8ccb3683012701a6d46c03b2c968c0b96d` |
| `test/wotex/ble/stream_bridge_test.exs` | `5d6aa2bb8bc287acab7e1a83cac9c8f686767fa6a00ced315d87cf8b10e58246` |
| `test/interop/virtual/native_gatt.py` | `e188f44614f59ad358658a461949d0346d1795d17062eb4c4ee86bf0ae72c83b` |
