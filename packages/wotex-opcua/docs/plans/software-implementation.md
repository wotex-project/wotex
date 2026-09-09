# WOP native software implementation sequence

This acceptance sequence defines the complete WOP.00/.10/.11/.12/.13 native
software profile. Current code/evidence is bounded by WOP.02 and
[executable evidence](../provenance/executable-evidence.md). A planned API or
fixture is not a completed implementation. Read CLAUDE, matching rules/skills,
all five target specifications, the source manifest and catalogue before work.

## Ordered work packages

Each package depends on all preceding packages. Existing valid pure values and
compatibility shapes remain part of its regression boundary. Package identifiers
are stable; a package may have several logical tested commits. The matrix is
binding implementation work, not a changelog.

| Package | Implementation and acceptance | Executable destinations |
| --- | --- | --- |
| WOP-P00 | X01/X02: pinned SDK/OpenSSL source admission, native Mix build task, package assets, versioned ready and digest validation; Opex reuse obeys the reviewed metadata/security boundary | native_build_test.exs; test/native/build_test.c; X01/X02 manifest/failure cases |
| WOP-P01 | S01/N02/N05: typed pure Variant/DataValue/ExpandedNodeId/QualifiedName/LocalizedText/reference codecs, exact signed ticks and array/null/opaque distinctions; lossless JSON integer/negative-zero IPC | typed_values_test.exs; test/native/value_test.c; WOP-F01..F13 and X-F01..F16 |
| WOP-P02 | S02/X03/X04: persistent native Session activation, explicit one-shot native projection, server/local namespace mapping, complete framed IPC, credit control, bounded async requests and cancellation/EOF cleanup | persistent_bridge_test.exs; test/native/session_test.c; X-F10..F23/X-F49..F55 plus split/coalescing/malformed/partial-open matrix |
| WOP-P03 | S03: all three SignAndEncrypt policies and all three user-token modes, pin/SAN/URI/CRL/key validation, immutable trust, no downgrade/reconnect/replay | test/native/security_test.c; test/interop/security_fault_test.exs; X-F30..F47 |
| WOP-P04 | S04/X05: raw service-level subscriptions, exact revised parameters, full DataValue/overflow metadata, bounded Publish ACK and Republish sequence state | subscription_test.exs; test/native/subscription_test.c; X-F24..F28 |
| WOP-P05 | C03/C05/S02/S04/X04/X05: receiver/Session/owner loss, cancellation failure, saturated output, partial-open/final-owner handoff and terminal-once cleanup | subscription_lifecycle_test.exs; test/native/lifecycle_test.c; X-F18..F23/X-F29 and suspended-owner overproducer stress |
| WOP-P06 | S05: typed Runtime Property observation and explicit health probe, native one-shot compatibility projection, unsupported Event/credential rejection | runtime_stream_test.exs; real Runtime child-spec lifecycle tests |
| WOP-P06a | N01/N03/N04/N05: typed bounded Browse/BrowseNext/release, original Session/deadline, early-release/failure fallback and native root helpers | standalone_contract_test.exs; test/native/browse_test.c; WOP-F14..F16 and complete N boundary matrix |
| WOP-P07 | X06/S01..S04: independent asyncua secure peer and same-stack exact-tick/fault C peer, typed methods/arrays/users, subscriptions and continuation counters; all policy/token/security cells execute | test/interop/asyncua_test.exs; test/interop/open62541_test.exs; full V01..V14 software assertions |
| WOP-P07a | I01..I06: exact profiles and Form/context/media selection, Result identity/metadata, complete Error/Retry table, final-owner custody and cleanup through real ConsumedThing | runtime_integration_test.exs; all wotex-integration-v1.json cases and I06 matrix |
| WOP-P08 | C09/C10/X06: complete software Mix tasks, audit/sanitizer/matrix/stress and isolated native archive consumer with no runtime Python; evidence contains every S/N/I/X assertion and current digest | test/software/lifecycle_stress_test.exs; X-F48; full software runner and out-of-tree package workflow |

Paths without a directory prefix in the table are under `test/wotex/opcua/`.
All referenced tests and Mix tasks are required implementation unless present
and already asserting the exact contract. No success-shaped placeholder, skipped
required facility, fixture echo or test identifier alone satisfies acceptance.

## Verification and evidence

Each package runs focused assertions, then the complete `WOTEX_PATH_DEPS=1 mix
check --no-retry` gate before its local commit. Native changes also run CTest and
the applicable audit/sanitizer lanes. Normal Hex dependency identity remains
authoritative; the path switch is development evidence only. Coverage and audit
thresholds remain intact. No knowingly failing package is committed.

`mix wotex.native.build --workspace ABS` supplies the production helper.
`mix wotex.software.build --workspace ABS` builds pinned disposable peers.
`mix wotex.software.run --workspace ABS` runs every required test, native audit
and cleanup assertion under WOP-X06. Workspace source/toolchain/options/binary
manifests reject unrelated contents and stale reuse. No task starts hardware,
configures a remote, publishes, tags or pushes.

A requirement record names its exact asserting test, case ID, corpus SHA-256,
source/archive/fixture identities, runtime/native cohort, command, exit status
and resource counters. Independent-peer, same-stack C, injected-contract and
pure-codec evidence remain distinct. Native DateTime exact-tick assertions use
the C lane; Python's normalized timestamps cannot discharge them. Required
missing setup is a failure under WOTEX_REQUIRE_SOFTWARE=1.

Final acceptance includes all C09 operation/concurrency/lifecycle counts, all
supported native OS/CPU cohorts, minimum/current Elixir/OTP, native dependency
audits, ASan/UBSan, remote cleanup/expiry counters and an isolated archive-only
consumer. Its runtime starts no Python, shell or compiler. Hardware testing,
certification, publication and consumer parity are separate claims and do not
excuse unfinished software. The catalogue and current-profile documentation
state only the cells with current executed evidence.
