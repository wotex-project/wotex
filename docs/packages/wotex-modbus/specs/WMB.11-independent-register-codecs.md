---
spec:
  id: WMB.11
  title: "Independent register codec reference programs"
  status: accepted
  version: 1.0.1
  owner: wotex-modbus
  updated: 2026-10-08
---

# WMB.11 Independent register codec reference programs

Two separately written C++17 and Rust reference programs implement WMB.09
through WRT.06 `process-codec@1.0.0`. They do not link a WoTEx decoder, open a
device, load consumer code or authorize an operation. Their only runtime I/O is
stdin/stdout protocol exchange. They are engineering reference executables;
passing their tests does not qualify a WMB.10 native enforcement driver.

## R01 — Source and build ownership

Each reference owns its parser, configuration verification, register projection
and canonical output. Shared inputs are the accepted contract/schema documents
and independently authored vectors. C++ uses the vendored nlohmann/json 3.11.3
header, SHA-256
`9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6`,
with its compatible MIT notice. Its first-party SHA-256 implementation follows
[FIPS 180-4, August 2015](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf)
and is checked against independent known answers; no certification claim.
Rust pins serde 1.0.228, serde_json 1.0.145, base64 0.22.1 and sha2 0.10.9.
Cargo.lock records its complete dependency cohort and archive checksums.
Cargo retrieves dependency sources and upstream notices into its external
cache; this repository does not vendor them. No WoTEx native admission derives
from those source pins.

Reference sources and test orchestration live under `test/native/` and
`test/support/`. Package-owned native descriptors distinguish the reference
profiles from the existing software peer. Builds record exact source, contract
and dependency identities, compiler/target and executable digest in a disposable
absolute workspace. No executable is committed or shipped in the normal package
archive. Tests add no default launcher or dependency-load side effect.

## R02 — Child exchange

The child accepts one hello, then sequential decode frames and stop.
Configuration must match the five-field WMB.09 grammar and its canonical
SHA-256 before ready. Contract id/hash must match the build's embedded contract.
Identity fields obey WRT.04/06 bounds and are echoed exactly. Decode budget is
`1..decode_ms`; seq begins at one and increases without wrap. Stop exits
successfully without a reply, including during startup. EOF exits without
inventing a result.

Read input in bounded chunks. Full frames including LF are at most 131,072
bytes; incomplete bytes leave space for LF. Process fragmented/coalesced input
in order without unbounded read-ahead. Apply WRT.06 JSON/node, flat-object, input
and Base64 expansion bounds. Reject duplicate keys, extra fields, BOM, raw
CR/LF, invalid Unicode, trailing bytes, floats/exponents, noncanonical Base64,
unsupported versions and direction/state substitutions. Protocol/configuration
failure exits nonzero without foreign text, downgrade, retry or BEAM fallback.

A valid decode frame produces exactly one canonical result or WMB.09 refusal
with unchanged seq/request id. Output is an inert decimal node, never a float.
The consumer host owns the original local deadline and actual memory,
privilege, immutable deployment and descendant enforcement.

## R03 — Reference evidence and qualification

Tests send real stdin bytes to compiled programs and validate raw canonical
output with public Runtime Wire and fixed expected vectors. Cover all widths/
orders, signed extrema, negative zero, scale normalization, refusals, repeated/
cross-instance output, Unicode request ids, frame cuts, coalescing, parser/field/
hash/version/counter faults and maximum/one-over bounds. SHA-256 checks include
empty input, abc and multi-block payloads. Errors/stderr expose no canaries.

Supported native reference targets mean functional executable cells, not a
production enforcement profile. Record executed cells separately. Linux loader
closure, clean offline artifact adoption, escaped-descendant custody, memory/
privilege limits, consumer costs and physical devices remain separate programme
gates. Neither test presence nor a source build promotes those claims.
