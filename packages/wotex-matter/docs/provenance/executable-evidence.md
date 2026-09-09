# Executable evidence

Current implementation: bounded paths/TLV, explicit Client contract and the
one-shot Python factory adapter. The committed documentation cohort `8f1f34a`
has a passing full local gate: 2 doctests, 1 property and 14 tests, one
interoperability exclusion; 96.6% coverage. Python SDK-contract tests use an
explicit test controller. No first-party persistent C++ controller, durable
authority, actual commissioning/CASE/attestation or subscription lane is accepted.
The .10/.11/.12/.13 controller/software-peer packages remain implementation work.
An arbitrary supplied factory is not a substitute for that acceptance.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Acceptance boundary

[WMA.13](../specs/WMA.13-native-backend.md) defines the required native binary,
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
| `test/bridge/matter_bridge_test.py` | `f2f41e95a68180c117433d395221d4984683e333edddad2f325cdb49fd52422b` |
| `test/wotex/matter/contract_test.exs` | `45d55f0df387085d6ed9f7667cc41267ce63e0c0e084578dbcb1b0150e8f8099` |
| `test/wotex/matter/sdk_test.exs` | `b7699b283063ce3884b24fa5e39d55a5834c359872567d3a225c330ed33673ae` |
| `test/wotex/matter/tlv_test.exs` | `eb245cee8ec6ae71543839d00b5faf2468c66a496c7e06695772a5dcab3fd242` |
