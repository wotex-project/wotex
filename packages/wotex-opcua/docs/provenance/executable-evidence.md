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

The native secure Session, credit protocol, complete 100 ns metadata and
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
| `test/wotex/opcua/binary_test.exs` | `bf2417a5fa093a59adaaf262ca08f614bbc995366961bead7df60b9de45c6a96` |
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

`standalone_contract_test.exs` executes WOP-F01, F02, F09 and F13 from
`contract-v1.json` through public `Binary` functions. The fixture input alone
reaches each decoder; the complete actual projection is compared with the
declared expectation. Test tags contain the fixture case, requirement IDs and
SHA-256 of the corpus bytes. `binary/names_test.exs` and
`binary/reference_test.exs` exercise exact masks and field order, all NodeId
kinds and NodeClasses, nullable/empty text, maximum string and URI lengths,
numeric overflow, every truncated field, invalid masks, and arbitrary byte
streams. Unconsumed tails remain byte-exact, including a tail larger than the
consumed identity limit. These checks cover the pure identity/reference subset
of N02; they do not accept Variant/DataValue, SDK construction or Browse services.
