# Wotex OPC UA

**A bounded OPC UA client for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_opcua.svg)](https://hex.pm/packages/wotex_opcua)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_opcua)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_opcua.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-opcua/LICENSE)

[Installation](#installation) ·
[Profile](#profile) ·
[Quick start](#quick-start) ·
[Ownership](#ownership-and-safety) ·
[Native build](#native-build) ·
[Development](#development)

## Installation

Wotex OPC UA 0.1 supports the minimum and current Elixir/OTP toolchains in
[`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
Add the package directly; Hex resolves `wotex` and `wotex_runtime` from its
published dependency requirements.

```elixir
def deps do
  [
    {:wotex_opcua, "~> 0.1"}
  ]
end
```

## Profile

The package implements an explicitly bounded OPC UA client profile through an
owned open62541 C executable. Runtime operation does not use Python.

The native client provides:

- persistent and one-shot secure Sessions;
- typed Read, Write and Method Call operations;
- numeric, string, GUID, opaque and namespace-URI NodeIds;
- bounded typed Browse, BrowseNext, release and child collection;
- monitored Value subscriptions with Publish acknowledgement, Republish,
  sequence validation, queue bounds and terminal cleanup;
- SignAndEncrypt with Basic256Sha256, Aes128_Sha256_RsaOaep or
  Aes256_Sha256_RsaPss;
- anonymous, username or certificate user tokens; and
- static Runtime profiles for Property reads and writes, plus persistent
  Property observation.

Typed values retain scalar/array/null distinctions, dimensions, full
StatusCodes, exact signed 100 ns DateTime ticks, picosecond fields and opaque
ExtensionObjects. The public one-shot mode preserves its documented successful
Read, Write and Call shapes; failures keep the native error code, effect and
Runtime class.

The profile intentionally excludes History, PubSub, EventFilter subscriptions,
redundant-server failover, reverse connect and certification. Runtime does not
advertise Action/Call Forms or Events: Call and Browse remain explicit native
APIs. Acknowledged writes and calls do not establish canonical application
state.

The same-stack C peer exercises exact SDK and security behavior. An independent
async-opcua Rust peer covers the complete policy/token and rejection matrices,
Browse continuations, Cancel, monitored values, Republish, lifetime expiry,
server loss, no-replay behavior and server-side resource counts. The
[specification catalogue](../../docs/packages/wotex-opcua/specs/catalogue.yaml)
maps every accepted contract to its executable owners.

## Quick start

Pure values and codecs need no native process:

```elixir
{:ok, node} = Wotex.OPCUA.Address.new("ns=2;s=temperature")
{:ok, bytes} = Wotex.OPCUA.Binary.encode_node_id(node)
{:ok, ^node, <<>>} = Wotex.OPCUA.Binary.decode_node_id(bytes)
```

The native client takes an explicit executable and digest, endpoint,
application identity, trust material, CRL, security policy and user-token mode.
Credential files are validated and copied into bounded request data before the
Session opens. Consumers own those paths and the process supervision around the
client.

For WoT consumers, `Wotex.OPCUA.profile/0` returns the one-shot Property
profile. `Wotex.OPCUA.profile(:session)` returns the persistent read, write and
observe profile. Both accept only `opc.tcp` Forms without `contentType`; this is
a native protocol value boundary, not a JSON or XML serializer.

## Ownership and safety

This is an ordinary Mix library. Loading it starts no application process,
opens no connection and reads no runtime file. Long-lived work starts only from
an explicit call or child specification.

Each native Session owns its guardian, SDK process, requests, continuations,
subscriptions and timers. Admission, network work and conversion share one
deadline. Session loss is terminal: outstanding work and subscriptions fail,
owned resources close and a replacement server requires an explicit new
connection. Writes and calls are never replayed automatically.

Errors are `%Wotex.OPCUA.Error{}` values with a finite code, field, effect,
retryability and Runtime class. Unknown-effect mutations are non-retryable.
Telemetry contains bounded operation/result/status dimensions, never
credentials, endpoint strings, values or arbitrary exception text.

Unknown Form extensions survive mapping but do not become executable options.
The endpoint selected by Runtime must match the configured native target. The
consumer supplies routing policy, credentials, supervision and canonical
Property truth.

## Native build

Build the pinned open62541 1.5.7 and OpenSSL 3.5.8 helper in a new, empty or
previously verified absolute workspace:

```console
mix wotex.native.build --package wotex-opcua --workspace /absolute/workspace
```

Inside the package, `mix wotex.opcua.native.build` and
`mix wotex.native.build` are equivalent. The task verifies source archives,
applies digest-checked SDK patches, builds static libraries and both native
executables, runs CTest and writes `wotex-native-build.json`. Reuse verifies the
entire receipt and every admitted artifact again.

The build needs network access, a C11 compiler, CMake 3.20 or later with CTest,
make, Perl, Python 3 for the upstream SDK generator, `ar`, `ranlib`, `ld` and
curl 8.4 or later. Supported build cohorts are Linux x86_64/aarch64 and macOS
arm64. Python is a build and isolated-audit tool only; neither the package nor
its repository-owned peers use it at runtime.

## Software evidence

The explicit software lane builds the native helper, same-stack C peer,
independent Rust peer, sanitizer tree and hash-locked audit environment:

```console
mix pkg wotex-opcua wotex.software.build --workspace /absolute/software
mix pkg wotex-opcua wotex.software.run \
  --workspace /absolute/software \
  --core-archive /absolute/wotex-0.1.0.tar \
  --runtime-archive /absolute/wotex_runtime-0.1.0.tar
```

The run verifies the build manifest, starts both peers, runs the interop and
software suites, ordinary and sanitizer CTest, Mix/Hex/Cargo/pip/native-source
audits, lifecycle stress and the exact-archive consumer. The consumer unpacks
exact core, Runtime and OPC UA candidates, builds the native helper from the
dependency, performs six secure public operations and proves that no Python,
shell or native helper remains.

These lanes do not publish anything or claim registry adoption. Current
platform evidence and refresh steps live in the
[qualification runbook](../../docs/packages/wotex-opcua/plans/qualification.md).

## Development

Run commands from the repository root:

```console
mix pkg wotex-opcua test test/wotex/opcua/value_test.exs
mix check.fast --package wotex-opcua
mix native.lint --package wotex-opcua
```

The ordinary test run excludes `interop`, `software`, `hardware` and
`native_build`. It needs `cc` because focused host and native-contract tests
compile first-party C fixtures. Native source changes also run the package's
native lint command; the full package gate adds clang-tidy, native CTest,
Dialyzer, docs, audits, the fresh native build, Hex archive inspection and the
Application-free check.

Use `mix pkg wotex-opcua check --no-retry` only for the complete package gate.
The explicit software runner is intentionally separate because it downloads and
builds the pinned SDKs and peers.

The detailed contracts are:

- [implemented profile](../../docs/packages/wotex-opcua/specs/WOP.03-implemented-profile.md)
- [secure software profile](../../docs/packages/wotex-opcua/specs/WOP.04-software-contract.md)
- [standalone client and preservation](../../docs/packages/wotex-opcua/specs/WOP.05-standalone-client-and-preservation.md)
- [Wotex integration](../../docs/packages/wotex-opcua/specs/WOP.06-wotex-integration.md)
- [native executable](../../docs/packages/wotex-opcua/specs/WOP.07-native-executable.md)
- [executable evidence](../../docs/packages/wotex-opcua/provenance/executable-evidence.md)

## License

Wotex OPC UA is released under Apache-2.0. See
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-opcua/LICENSE)
and [NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-opcua/NOTICE).
