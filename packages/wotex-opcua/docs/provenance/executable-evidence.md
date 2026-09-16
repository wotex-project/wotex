# Executable evidence

Evidence collected 2026-09-08 using Elixir 1.20.2 / OTP 29.0.4.
That historical baseline covered the stated toolchain only. The package
requires fresh source-specific matrix and archive checks before graduation. No consumer parity or
certification is inferred from unit coverage.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. The native build test is required by this
gate: it downloads the pinned archives, executes the static build and CTest, and
checks receipt reuse/tampering in an owned temporary workspace. The gate requires
CMake 3.20+, a C11 compiler, make, Perl, Python 3, archive utilities and curl 8.4.0+.
`mix test` excludes this lane; selecting `native_build` without its explicit
`WOTEX_NATIVE_BUILD_WORKSPACE` fails. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## WOP-P00 source, build and custody cohort

WOP-P00 passed on 2026-09-14 for the source/build/bootstrap and portable
process-custody boundary. `WOTEX_PATH_DEPS=1 mix check --no-retry` used Elixir
1.20.2 / OTP 29.0.4 on macOS 26.6.2 arm64. Coverage was the only ExUnit pass:
254 tests passed, one interoperability tag was excluded, and coverage was 96.3%.
The selected native build downloaded and verified the pinned source archives,
built static OpenSSL/open62541 and both first-party executables, then passed all
161 CTest cases. The native CTest output SHA-256 was
`e79c866df4d8debb3cdba9e8b9126b46f3ccba07cf2e987680b091c52da7442e`.

The build receipt bound these identities:

| Subject | SHA-256 |
| --- | --- |
| native source manifest | `909bb2cca1eeb20e755af093cc24b896ba94b578b81ee25d4924cfc406ae73b9` |
| open62541 1.5.7 source archive | `a4018b052c93fedb55f00558a85869b86f3bb2293184d322e33f2666c497eaeb` |
| OpenSSL 3.5.8 source archive | `59f86483992995df5a213df38d93f31eeafe3b34599309b3e088ba67ca0aad9c` |
| macOS arm64 `wotex_opcua_native` | `8c52d02d2ab66d95c36e9d5266ca8b5d15b24107837178f5656a2ebaeaeb3781` |
| macOS arm64 `wotex_opcua_custody` | `c3cd34e996542c79fbc9031e8067bb41bbe7415a5132e981c7a72db1296e5197` |
| custody fixture | `bd69b4c0bff4a43ae7318c95702d23e925ca93190c62bc88f52b508b4b306144` |
| runtime guardian source | `d08b553ed0cd4ba9b166e8b01aae8eddd96f97a8accc418632d68e3c75ad37d2` |
| independent custody driver | `ef8c45b3bea8727a8a9e6be0fe4985d8a798ff0d5bee1b870a6346f5ede498e5` |

WOP-G10 additionally passed in Linux arm64 and x86_64 containers resolved from
`debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171`.
Each architecture executed WOP-G01 through WOP-G09 once with strict
AddressSanitizer/UndefinedBehaviorSanitizer timing and once with LeakSanitizer:
18 executions per architecture, zero failures. The independent Linux driver
asserted exact byte/count/status projections, SDK reap within 500 ms, guardian
exit within the applicable allowance, and absence of leaked direct children.
`bin/check_native_custody.exs` makes those Linux sanitizer lanes part of the
default gate; macOS runs the portable corpus through the native build and CTest.

This evidence accepts P00 only. The native helper still exposes dependency and
bootstrap behavior, not a secure Session or application service. P01 and later
packets, complete native service framing, independent peers, the full platform
matrix and an archive-only native consumer remain required separately.

## WOP-P01 typed value and namespace cohort

The P01 gate uses Elixir 1.20.2 / OTP 29.0.4 on macOS arm64 with the locked
development dependencies. `WOTEX_PATH_DEPS=1 mix check --no-retry` passes 254
checks (10 doctests, 4 properties and 240 tests), with one interoperability test
excluded and 96.3% coverage. The required fresh native build passes 178 CTest
cases, including every WOP-X-F01 through WOP-X-F16 projection and WOP-NF17
namespace fault case. Build receipts bind the native contract fixture separately
from the first-party source files and upstream archives.

A separate Debug build enables `WOTEX_SANITIZERS=ON` and runs
`ctest --output-on-failure -R 'native_(value|contract|json)'` with
`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`. All 167 selected tests pass on macOS arm64.
The same 167 cases also pass on Linux x86_64 with leak detection enabled,
using the pinned Debian image recorded for P00, GCC 12.2.0 and CMake 3.25.1.
Both builds instrument the first-party native sources and parser with
AddressSanitizer/UndefinedBehaviorSanitizer; their static SDK and OpenSSL inputs
retain the pinned versions recorded for P00 and are not sanitizer-instrumented.

An isolated Elixir 1.18.4 / OTP 27.3.4.15 run passes the default suite:
10 doctests, 4 properties and 241 tests, zero failures and two exclusions
(`interop` and `native_build`). That run does not repeat the SDK build.

| P01 input | SHA-256 |
| --- | --- |
| native contract corpus | `b1505300b4bcb5d0fd596c67a6e027bcbef123b386c8f379f0bd0ecf5e995ec1` |
| typed value corpus | `b38f6fc3b8ea23fd55a2c899146bb643376b6e4ace9af3b71d1221615b0db1ec` |
| native contract runner | `748535edab646afbe7847f5e4af8d42c824fa05c72850ebea0033918465ac0f9` |
| value codec implementation | `ef7a4b16e6485fec0f903e2f55aedadf3a982fa0c662ec0bb07cb5a781ba7593` |
| value codec header | `1aeef02790f45be1071ec6a0063cb40d70b8e4e49880b60b876052187e658b16` |
| direct SDK fault runner | `433783382e1b74dc6560440e5af2f14359af07c754819dd41f128b875c362c4f` |

P01 accepts pure typed values, identity/reference preservation, SDK value
projection and exact namespace translation. The namespace arrays are explicit
inputs to a pure primitive. Their acquisition and lifetime, native Sessions,
services, subscriptions and independent peers remain required by later packets.

## Initial WOP-P02 input boundary (package remains open)

On 2026-09-16, the actual `wotex_opcua_native` process used `ipc.c` and the
strict production JSON reader to assemble and validate an outer request line.
`native_ipc_admission` exercises every split of its valid line, two coalesced
lines, the exact frame ceiling, NUL rejection, closed keys, duplicate keys,
exact integer endpoints and malformed envelope fields. The required native
build test speaks to the installed executable through a real Port and asserts
ready followed by exactly one terminal for split valid input, expired deadline,
fractional timeout and duplicate ID. No SDK service request is sent.

`WOTEX_PATH_DEPS=1 mix check --no-retry` passed 254 checks (10 doctests, four
properties, 240 tests), one excluded interoperability test and 96.3% BEAM
coverage. Its selected native build rebuilt the pinned sources, ran CTest and
checked receipt tampering. A separate CMake build against the already verified
pinned static prefixes passed 179/179 CTest cases. A Debug
`WOTEX_SANITIZERS=ON` build with `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`
and `UBSAN_OPTIONS=halt_on_error=1` passed 168/168 selected
`native_(ipc|json|value|contract)` cases on macOS arm64. These local runs do
not establish Linux sanitizer coverage for the new slice.

| P02 input source/evidence | SHA-256 |
| --- | --- |
| `priv/native/ipc.c` | `39a10286f82841f74b323f98c5d225ccb1f5d6297d5b85538f19a8a27aa2be1f` |
| `priv/native/ipc.h` | `cd603dc0ad185f52cd23210e89107bebb2420dad40d4fb26faac22926e035e3a` |
| `priv/native/main.c` | `c388e31dbcee974bb032a9221aca73c76f5aecd1eaca9eceeab41e9461baabeb` |
| `priv/native/ipc_check.c` | `731617b3cc25db22036d557e54633e5eb99477b4592d940e58d908f26b61f55c` |
| `test/wotex/opcua/native/build_test.exs` | `a2a4d40235b7f6e5ea858634bba5baa8a59658f41deff14fcb94da9e7dbfefcb` |
| local normal CTest log | `30b15182ed0c19767c2ee50327aca1d67256c449413beef94db8ee47af4f8ebe` |
| local sanitizer CTest log | `dd8819b7bc7f05582a58c8fb804739d531bd009e44399d003f857d24e8a49932` |

This is a process-input and terminal-rejection slice, not acceptance of P02.
Per-operation parameter validation, persistent Session activation, namespace
acquisition, credits, responses, cancellation and all X-F17..F23/X-F49..F57
remain required. The current Python adapter still owns public network operations.

## Implemented Python-adapter interoperability

Real secure asyncua 2.0.1 peer: PASS for read, write/readback/restore, browse,
unknown-node failure, expired certificate, wrong host/URI, untrusted CA and
revoked certificate. Both sides use asyncua; this is a real wire/security proof,
not independent-stack interoperability or OPC Foundation certification.
Intermediate trust chains are outside the implemented security profile.

```sh
python3 -m venv /tmp/wotex-ua-test
/tmp/wotex-ua-test/bin/pip install -r priv/requirements.txt
/tmp/wotex-ua-test/bin/python test/interop/secure_peer.py /tmp/wotex-ua-fixture
# In a second terminal, after config.json exists:
WOTEX_PATH_DEPS=1 WOTEX_OPCUA_INTEROP_CONFIG=/tmp/wotex-ua-fixture/config.json mix test --include interop test/interop/asyncua_test.exs
```

Stop the explicitly started peer afterward. The fixture generates disposable
keys/certificates outside the repository; do not use them as operational trust.
The Python requirements are fully version-pinned. The Elixir gate does not
install Python dependencies; audit the optional environment separately with
`pip-audit --disable-pip --no-deps -r priv/requirements.txt`.

Interoperability tags are excluded by default. Explicit invocation requires the
configured peer and must fail if that peer or expected response is missing.

## Evidence identities

The native build tests under `test/wotex/opcua/native/` cover source admission,
workspace ownership, guarded commands, static build, dependency self-test and
receipt validation. Each completed build records separate source, build-code,
tool, option and artifact hashes in `wotex-native-build.json`; its command logs
are also hash-bound. The executable's one-tick SDK check is a dependency test,
not complete DataValue metadata or wire interoperability evidence.

The native secure Session, credit protocol, end-to-end 100 ns metadata and
independent asyncua/native workflow remain required implementation. Software
build/run entry points remain specified work. The interoperability command above
exercises the current Python runtime adapter.

The hashes identify reviewed test sources, not an immutable release or a promise
that all future test executions will pass. The mandatory gate and optional peer
commands above must be rerun after relevant changes.

| Test source | SHA-256 |
| --- | --- |
| `test/interop/asyncua_test.exs` | `d1eb6dae68bc989ccb5b1df7778d80c9512781cdcc2fb248d4c43b1a09567740` |
| `test/wotex/opcua/asyncua_test.exs` | `d36277d2fd7ec90e6fb393f19ee6730c600e6e83713190e83146dfce67182e6e` |
| `test/wotex/opcua/binary_test.exs` | `a173b9a4687c7965e4b45eab7809b066a428c0de26fe254f230e2fb7a8f23a9b` |
| `test/wotex/opcua/contract_test.exs` | `e9d677fe79d5d8b4fdb88d1d597b0d6bb3cb2bdbe2889a9cc4003432cb5e5f33` |
| `test/wotex/opcua/dependency_security_test.exs` | `3c45b778a241b2a577f9481c6a7ec08f4f8ec747f72a6d5e7deaf3265510e072` |
| `test/wotex/opcua/mapping_test.exs` | `2768c115820bcd56364bde5d2101bc13dc242fc92f5ca0a2c1b62b01e7812f93` |
| `test/wotex/opcua/port_test.exs` | `bf7dfcf70fa9afc680f07d4b861c56ecf954b01e8d280b12d7981849cc19cb48` |
| `test/wotex/opcua/value_test.exs` | `5c173dfdd5a27d60887064fe64041a3d5fd2434442bcd8abe431e00345f96089` |

## Native runtime custody

`test/wotex/opcua/native/custody_test.exs` executes the checked-in
`custody-contract-v1.json` cases using `priv/native/custody_check.c`. CTest repeats
those nine native cases during each actual SDK build. Assertions cover exact
fragmented bytes, simultaneous traffic, owner EOF with full pipes, stopped SDKs,
receiver loss, contained stderr, complete final output, blocked final drains,
group isolation and one shared cleanup deadline. The Linux test driver audits
orphan adoption independently of the guardian. A separate LeakSanitizer lane
retains the 500 ms SDK reap bound and explicitly reports instrumentation-only
post-main exit time; ordinary and ASan/UBSan timing lanes retain the 500 ms total
guardian bound. The [runtime custody contract](../../priv/native/runtime-guardian.md)
defines those separate acceptance conditions. These checks do not implement or
accept SDK frame credits, secure Sessions or OPC UA subscription ownership.

## BEAM native bootstrap

`native/ready_test.exs` executes every exact frame in `native-ready-v1.json`.
`native/executable_test.exs` exercises bounded file admission and SHA-256 identity.
`native/host_test.exs` compiles the real custody guardian with a separate C fault
peer, then asserts malformed readiness, fragmented output, failed executable
admission, stopped SDKs, owner death during hashing and readiness, post-startup
loss, and a suspended claimant's original deadline. A temporary Supervisor child
does not restart a failed host. Each started fault peer records both native
process identities and the tests check their absence after cleanup; the separate
C custody driver verifies direct-child reaping.

The required native build test starts the installed SDK helper and guardian
through `Native.Host` using their receipt digests. This is a real process-ready
integration check without an OPC UA endpoint or service. It does not accept a
secure Session, application data, subscription credit flow or remote cleanup.

## Native JSON syntax and numbers

`native/json_test.exs` compiles the reviewed parser and first-party adapter, then
executes every case in `native-json-v1.json` through the bounded command guardian.
The driver receives only the input frame and allocator size, and returns parsed
node counts, exact integer projections and IEEE-754 bit patterns. The tests
compare the complete declared output. Long frame boundaries use an exact prefix,
space count and suffix instead of repeated literal whitespace in the fixture.
The CTest self-test separately exercises strict flags and basic pool ownership.
Vendor tests reject missing, altered and symbolic source/license files. These
checks do not accept typed SDK construction, response serialization or services.

## Pure identity and reference structures

`standalone_contract_test.exs` executes WOP-F01 through F13 from
`contract-v1.json` through public `Binary` functions. The fixture input alone
reaches each decoder; the complete actual projection is compared with the
declared expectation. Test tags contain the fixture case, requirement IDs and
SHA-256 of the corpus bytes. `binary/names_test.exs` and
`binary/reference_test.exs` exercise exact masks and field order, all NodeId
kinds and NodeClasses, nullable/empty text, maximum string and URI lengths,
numeric overflow, every truncated field, invalid masks, and arbitrary byte
streams. Unconsumed tails remain byte-exact, including a tail larger than the
consumed identity limit. `typed_values_test.exs` exercises every supported
Variant type, null/empty arrays, dimensions, future numeric type preservation,
opaque binary/XML bodies, mixed-endian GUIDs and exact adjacent timestamp ticks.
DataValue assertions cover metadata masks, Bad/Uncertain status, present null
versus absent data, clamped/orphan fractions and the complete 1 MiB byte budget.
These checks cover the pure value and identity/reference structures of N02;
they do not accept SDK construction or Browse services.

## Native typed value conversion

`priv/native/fixtures/value-v1.json` contains 133 concrete JSON inputs and exact
Part 6 binary results or typed rejection results. The required native build
executes each case separately through `value_check` against pinned open62541
1.5.7. The constructor retains exact signed and unsigned integers, DateTime
100 ns ticks, explicit array shapes and encoded ExtensionObject identities.
The checker clears and overwrites the parser storage before SDK encoding, then
clears the SDK arena before serializing the projected result. Rejected inputs
must leave no result and restore the arena checkpoint.

`value_fault_check` adds 17 direct SDK structure cases. They cover invalid
parameters, unknown types, dimensions, finite floating values, UTF-8, namespace
conflicts, DataValue flags, allocation exhaustion and size boundaries. Maximum
1024-element arrays, 65536-byte strings and byte bodies, and an exactly 1 MiB
encoded Variant succeed. The corresponding excessive values fail. An input
constructor cannot mask these direct SDK faults by rejecting them first.

The source-bound native build receipt includes the corpus, both test drivers,
typed library sources and CTest log. The [value codec contract](../../priv/native/value-codec.md)
defines its arenas and result lifetimes. This evidence accepts conversion
primitives only. SDK network-decoder allocation checks, received reserved type
IDs, complete framed service output, native Session ownership and independent
peer metadata workflows remain separate required implementation.
