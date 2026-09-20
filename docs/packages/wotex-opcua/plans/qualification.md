# OPC UA qualification runbook

The repository implementation is complete. This runbook records how to refresh
environment-dependent evidence without reopening source specifications or
mistaking a local checkout for a published artifact.

## Cohorts

Qualify the explicit software runner on the minimum and current Elixir/OTP
versions from `tooling/packages.yaml`. Record the exact runtime patch versions,
operating system, CPU architecture, compiler, CMake, Cargo and curl versions.
The native build supports Linux x86_64/aarch64 and macOS arm64; a receipt applies
only to the cohort that produced it.

Linux qualification runs both ordinary CTest and the ASan/UBSan/LeakSanitizer
tree. macOS runs the supported ASan/UBSan subset and must not claim
LeakSanitizer. A missing platform receipt is an evidence gap for that platform,
not an unimplemented source behavior.

## Build

From clean committed source, create a new absolute workspace and exact core and
Runtime archives from the same commit:

```console
mix pkg wotex hex.build --output /absolute/wotex-0.1.0.tar
mix pkg wotex-runtime hex.build --output /absolute/wotex_runtime-0.1.0.tar
mix pkg wotex-opcua wotex.software.build --workspace /absolute/new-workspace
```

The build must verify the pinned open62541, OpenSSL and yyjson sources, apply the
digest-checked SDK patches, compile the C helper and same-stack peer, build the
independent Rust peer from its exact lock offline after the allowed fetch, and
write `software-build.json`.

## Run

```console
mix pkg wotex-opcua wotex.software.run \
  --workspace /absolute/new-workspace \
  --core-archive /absolute/wotex-0.1.0.tar \
  --runtime-archive /absolute/wotex_runtime-0.1.0.tar
```

The run must pass the interop and software suites, native and sanitizer CTest,
Mix and Hex audits, the hash-locked pip audit, Cargo audit under the documented
loopback-only exception, the native OSV source audit, lifecycle stress and the
exact-archive consumer. Required peer, tool or audit absence is a failed cohort,
not a skipped pass.

Record the source commit; all three archive digests; corpus, adapter, peer and
lock digests; `software-build.json`, `software-run.json`, native audit and
archive-consumer digests; commands and exit statuses; operation counts; peer
resource counters; local process cleanup; and sanitizer results. Store
machine-local logs outside tracked source. Add only durable, reviewed receipt
summaries to executable evidence.

## Published artifacts and devices

Registry publication, repository visibility, hosted-artifact adoption,
certification and physical server validation are separate maintainer actions.
Never change repository visibility, publish, tag or claim those results from
this runbook. An immutable released-artifact adoption test may consume an
already published version, but it cannot perform publication itself.
