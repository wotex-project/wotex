# Executable evidence

Implementation commit `848312a8deb3a18e2ded0b5103ea1a2e2964831d` passed the full
local gate on Elixir 1.20.2 / OTP 29.0.4 and Elixir 1.18.4 / OTP 27.3.4.15.
Both lanes executed 214 cases (four properties and 210 tests); the three optional
interop/software cases remained excluded. Coverage was 95.5% and 95.4%,
respectively. These results establish that source's local native/Runtime test
boundary. They do not establish independent C-peer COV or the complete WBA-P06
software workflow.

The tested implementation tree was
`9a8df0d569b8b50cf665de3f9011ba8e9618d3d6`. Both lanes produced archive SHA-256
`6197f31dfad80afaa8041bff470f1026b691c33472b1fad4ca9061bc29eb15d0`.
These hashes identify that tested implementation and archive, not a published
release. No consumer parity or certification is inferred.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Interoperability

Independent BACnet C stack at commit
`3603048350b8ba543ec76cf6aa8a232b3f4d442d`: PASS for Analog Output 1 Present_Value,
write/readback/restore and unknown-object Error. The test owns its complete
BACstack group with retries disabled and exercises actual UDP transport.
No COV, routed network, MS/TP or BACnet/SC claim follows.

```sh
docker build -t wotex-bacnet-peer test/interop/cstack
docker run --rm -d --name wotex-bacnet-peer -p 127.0.0.1:57808:47808/udp wotex-bacnet-peer
WOTEX_PATH_DEPS=1 WOTEX_BACNET_INTEROP_PORT=57808 mix test --include interop test/interop/cstack_test.exs
docker stop wotex-bacnet-peer
```

Container source commits are pinned. Base-image/package-manager inputs may move;
these are reproducible source fixtures, not claims of bit-identical image builds.
Interoperability tags are excluded by default. Explicit invocation requires the
configured peer and must fail if that peer or expected response is missing.

## Current software acceptance boundary

The standalone F01–F11 corpus has local pure/adapter bindings listed in WBA-N05.
Runtime I-F01 is bound to real ConsumedThing execution. Each I-F02–I-F07 case
has a separately named executable test in `error_class_test.exs`. It supplies
the corpus native error code and effect to the library classifier, executes the
real Transport and ConsumedThing path, then compares the complete Runtime error
and Retry projection. The expected class never enters the protocol client.
A corpus assertion requires all seven case IDs and their local bindings; an
empty or incomplete case list fails. These injected native-error cases establish
the Runtime boundary, not independent wire-fault behavior.
Local COV and Runtime lifecycle tests exercise the native BEAM wrapper over UDP
fault peers. Independent object-COV evidence comes from the separate C suite
described below.

The checked-in `build_software.sh` and `run_software.sh` exercise the read/write
fixture. They accept environment configuration and do not implement the target
absolute-workspace admission or complete source/toolchain/binary manifest.
The required Mix build/run tasks, independent C-peer Property COV, full
receiver-death stress and final software matrix/archive cohort remain required.
A COV listener or final receiver queue bound does not bound an earlier
SDK-to-StackOwner mailbox.

The S03a receive pipeline has executable unit/property and local UDP tests.
`ingress_window_test.exs` binds accounting projections of IG01–IG03 and
`ipv4_packet_test.exs` exercises the pinned codecs. `ingress_lifecycle_test.exs`
binds IG01–IG06 to actual transport handlers, owned process cleanup, verified
borrowed capabilities and sustained UDP. For each separately suspended
StackOwner/StackClient, 10000 datagrams of 1536 bytes produce a peak of eight
outstanding receipts, zero armed sockets at exhaustion, one terminal
`:slow_consumer` and released owned processes/socket. Counter saturation uses
the actual transport handler; the 65507-byte deterministic input does not claim
the host OS accepted that UDP payload size.

Additional fault cases cover timer cancellation, forged acknowledgments,
malformed datagrams, actual socket closure and a 64-session watcher ceiling.
`ipv4_interface_test.exs` covers explicit IPv4 selection among multiple interface
addresses without changing any host interface. Actual receive buffer sizes are
recorded; kernel packet loss is unavailable through the selected portable inet
API and is never reported as zero. These local tests do not replace the required
Linux independent C-peer workflow, final supported matrix or complete C09 stress.

## Independent C object-COV execution

The instrumented [C fixture](../../test/interop/cstack/README.md) links the
unmodified pinned C stack. WBA-CP01's native parser/counter checks and WBA-CP02
through WBA-CP09's eight ExUnit cases pass on Linux ARM64 with GCC 12.2.0,
both normally and with ASan/UBSan applied to the fixture and linked SDK. The
ExUnit subject uses Elixir 1.20.2 / OTP 29.0.4 and actual UDP transport.

The suite observes Who-Is/I-Am, three sequential Property reads, write/readback
and priority release through a second actual client. Confirmed and unconfirmed
object COV deliver Present_Value and Status_Flags. Successful renewal changes
the actual SDK subscription record. ACK-loss cases apply registration/renewal/
cancellation in the C stack, then drop only the outgoing acknowledgment. A lost
cancellation request leaves an observed server subscription after local cleanup;
the finite server lease subsequently expires. Tests assert actual subscriber,
Invoke ID, ACK and cancellation counts, native process exits and socket release.

Peak native RSS is reported separately from live resource counts. These cases
do not establish SubscribeCOVProperty, complete C09 stress or the final immutable
package consumer cohort. The fixture's explicit source/options and counter
semantics are part of its contract, not a claim of general-purpose server support.

## Evidence identities

The hashes below identify test sources from implementation commit
`848312a8deb3a18e2ded0b5103ea1a2e2964831d`. They are source identities, not a
promise that later executions will pass. Rerun the mandatory gate and the
required peer suites after relevant changes.

| Test source | SHA-256 |
| --- | --- |
| `test/interop/cstack_test.exs` | `c489e4c14cd192ea8b221706d24a239a90c51a6f52be8da173c719b4190bf0c3` |
| `test/wotex/bacnet/stack_lifecycle_test.exs` | `0d097a4eca6f527d2c8d5a0b7edaea126a5c82de4f4a829aa0d440d6524acfd4` |
| `test/wotex/bacnet/service_boundary_test.exs` | `0b594b12ce8678055a046834f9931b9fb8f196554182f9c7a7c2927f4f061b78` |
| `test/wotex/bacnet/character_string_test.exs` | `cb77f9febdfa26db22a2f518295f2e958b2aa59054fe85ee4b21db2ec6734476` |
| `test/wotex/bacnet/cov_lifecycle_test.exs` | `7df574aa3fea2976930c24f5685404418483b33ce353b642308b959f130b7862` |
| `test/wotex/bacnet/standalone_contract_test.exs` | `eb9d3d1c26cc5bfda3e3da30f44826c66ad066bb91911103b0e4128ba0824ed7` |
| `test/wotex/bacnet/discovery_lifecycle_test.exs` | `4572d50b9a0d386587096f20c9859a70664e4ddf7a02148836df9d8f7dfc7285` |
| `test/wotex/bacnet/runtime_stream_test.exs` | `c16783cd63fef66dffc0262bc610595802022b77e6129038a3b40a56c973f4ea` |
| `test/wotex/bacnet/runtime_integration_test.exs` | `81526f9ee70be6495bb12763d545c8c673f186b93797e77568f158d6d97ec0ca` |
| `test/wotex/bacnet/error_class_test.exs` | `a5ebbe39edbacdc6dbd451662405228251a6fd563c4b4c08ecc91d9be23027db` |
| `test/wotex/bacnet/native_subscription_test.exs` | `843247062474e4d01546cd5254c2895e6d004b4228612ebdfec838abbd62e9bf` |
