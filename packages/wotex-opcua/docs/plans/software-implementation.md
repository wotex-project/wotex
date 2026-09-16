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

| Package | Implementation and acceptance | Executable destinations | Status |
| --- | --- | --- | --- |
| WOP-P00 | X01/X02/X07: pinned SDK/OpenSSL source admission, native Mix build task, separate bidirectional custody guardian, package assets, versioned ready and both executable digests; Opex reuse obeys the reviewed metadata/security boundary | native/build_test.exs, native/build_fault_test.exs, native/workspace_test.exs; native host ready/digest/EOF tests; X01/X02 manifest/failure cases and WOP-G01..G10 native custody cases | Accepted |
| WOP-P01 | S01/N02/N05: typed pure Variant/DataValue/ExpandedNodeId/QualifiedName/LocalizedText/reference codecs, exact signed ticks and array/null/opaque distinctions; lossless JSON integer/negative-zero IPC | typed_values_test.exs; production native value/contract checks; WOP-F01..F13 and X-F01..F16 | Accepted |
| WOP-P02 | S02/X03/X04: persistent native Session activation, explicit one-shot native projection, server/local namespace mapping, complete framed IPC, credit control, bounded async requests and cancellation/EOF cleanup | persistent_bridge_test.exs; test/native/session_test.c; X-F10..F23/X-F49..F57 plus split/coalescing/malformed/partial-open matrix | Open; native process and BEAM owner now activate/correlate/close one secure peer Session with revised timeout, NamespaceArray and response credit; services and full lifecycle remain |
| WOP-P03 | S03: all three SignAndEncrypt policies and all three user-token modes, pin/SAN/URI/CRL/key validation, immutable trust, no downgrade/reconnect/replay | priv/native/security_check.c; test/native/security_test.c; test/interop/security_fault_test.exs; X-F30..F47 | Open; native credential preflight and SDK verifier/configuration implemented; independent-peer matrix and production integration remain |
| WOP-P04 | S04/X05: raw service-level subscriptions, exact revised parameters, full DataValue/overflow metadata, bounded Publish ACK and Republish sequence state | subscription_test.exs; test/native/subscription_test.c; X-F24..F28 | Open |
| WOP-P05 | C03/C05/S02/S04/X04/X05: receiver/Session/owner loss, cancellation failure, saturated output, partial-open/final-owner handoff and terminal-once cleanup | subscription_lifecycle_test.exs; test/native/lifecycle_test.c; X-F18..F23/X-F29 and suspended-owner overproducer stress | Open |
| WOP-P06 | S05: typed Runtime Property observation and explicit health probe, native one-shot compatibility projection, unsupported Event/credential rejection | runtime_stream_test.exs; real Runtime child-spec lifecycle tests | Open |
| WOP-P06a | N01/N03/N04/N05: typed bounded Browse/BrowseNext/release, original Session/deadline, early-release/failure fallback and native root helpers | standalone_contract_test.exs; test/native/browse_test.c; WOP-F14..F16 and complete N boundary matrix | Open |
| WOP-P07 | X06/S01..S04: independent asyncua secure peer and same-stack exact-tick/fault C peer, typed methods/arrays/users, subscriptions and continuation counters; all policy/token/security cells execute | test/interop/asyncua_test.exs; test/interop/open62541_test.exs; full V01..V14 software assertions | Open |
| WOP-P07a | I01..I06: exact profiles and Form/context/media selection, Result identity/metadata, complete Error/Retry table, final-owner custody and cleanup through real ConsumedThing | runtime_integration_test.exs; all wotex-integration-v1.json cases and I06 matrix | Open |
| WOP-P08 | C09/C10/X06: complete software Mix tasks, audit/sanitizer/matrix/stress and isolated native archive consumer with no runtime Python; evidence contains every S/N/I/X assertion and current digest | test/software/lifecycle_stress_test.exs; X-F48; full software runner and out-of-tree package workflow | Open |

Paths without a directory prefix in the table are under `test/wotex/opcua/`.
All referenced tests and Mix tasks are required implementation unless present
and already asserting the exact contract. No success-shaped placeholder, skipped
required facility, fixture echo or test identifier alone satisfies acceptance.

The status column applies to the exact sources, toolchains and executions in
the evidence document. P00 acceptance establishes source/build/bootstrap and
portable guardian custody only. P01 adds pure typed values and native SDK value
projection, including an exact-match namespace translation primitive; it does
not acquire a server NamespaceArray or accept a secure native Session or any
later service, subscription, Runtime, peer, stress or archive-consumer packet.
The initial P02 input slice executes the strict parser inside the SDK process,
validates a closed outer request envelope and rejects expired native deadlines.
The pure BEAM `Native.Frame` encodes the outer request and conservatively maps
the separately sampled owner clock onto the native clock. The native build
test passes that encoded frame to the actual executable.
The internal host now sends a single owner-bound frame through custody and
decodes one generation-matched terminal error; invalid or unsolicited output
ends that process. A correlated secure open/close response is now admitted and
replenishes consumed credit.
Native `open` parameters now reject unknown keys, insecure modes/policies,
noncanonical bytes and invalid user-token/timeout shapes before any SDK I/O.
Native credential preflight now verifies DER/PKCS#8, RSA key pairs, direct-CA
trust, certificate usage/validity/signatures, exact SAN/URI and the issuer CRL.
Its C-generated test corpus includes positive and negative credentials. The
reusable peer verifier now runs as an SDK callback in a separate C Session
probe. Configuration tests cover all three policy names and user-token shapes;
the independent peer proves one Basic256Sha256 anonymous Session and explicit
NamespaceArray read in both the C probe and production owner. This is a
security prerequisite of P02, not acceptance or reordering of P03.
The owner and C ingress now share an explicit first credit control and fixed
generation. Open/close output consumes credit and the BEAM owner replenishes it;
bounded service/report queues remain required. The production open/close path
does not accept P02 or X-F17..F23 as a complete family.
The SDK build now preserves the server's actual revised Session timeout through
one digest-checked patch. Three real SDK Sessions against an isolated C loopback
peer verify fractional and integer values, copy lifetime and cleanup. This
test-only Security None lane is a prerequisite for accurate native open metadata.
The new pinned secure discovery patch, C probe and executable owner cover one
independent secure peer. The full service, lifecycle and policy/token matrix
remains open.

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
