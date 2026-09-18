# Wotex BLE package contract

Wotex BLE (`packages/wotex-ble`, Hex `wotex_ble`) owns Bluetooth Low Energy
GATT values, bounded protocol operations through two explicit Linux BlueZ
backends (one-shot `busctl` and the persistent first-party C++ host with its
runtime guardian), pairing through a consumer Agent, Form mapping, the Runtime
Transport and subscription relay, and a neutral compatibility adapter. Wotex
core owns W3C Web of Things values and Wotex Runtime owns interaction
mechanics; consumers own policy, credentials, supervision, connection
configuration and canonical Property truth. Repository-wide rules are in the
root `CLAUDE.md`.

## Invariants

- Production protocol execution uses the first-party C/C++ Port specified in
  WBL.07. Generic build/fixture orchestration and assertions use Mix/ExUnit.
  Python is limited to required upstream build tools or justified independent
  test peers.
- Specifications state contracts declaratively; implementation status and
  evidence are separate. Do not write changelog or migration narratives.
- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  application callback, framework integration or automatic network activity.
- Loading the dependency starts no process and performs no runtime filesystem
  access. Stateful transports start only through explicit calls or child
  specifications.
- Pure values never consult application environment, clocks or random sources.
  Transport time, identifiers, deadlines and ports have explicit ownership.
- Never fetch remote JSON-LD contexts. Preserve unknown Form extensions.
- TD 1.1 is the baseline. Label binding drafts as drafts; a mapped Form proves
  neither authorization nor a physical effect.
- Public functions have documentation and types. One module per `.ex` file.
  Test modules use `@moduledoc false` followed by a blank line.
- Errors are structured, input and allocation limits explicit, security modes
  fail closed, and write requests are never silently retried.
- Consumer neutrality is a review obligation; never add a consumer denylist.

## Where things are

- `lib/wotex/ble.ex`: the `Wotex.BLE` facade: compatibility callbacks,
  discovery, typed read/write, pairing, subscriptions and `profile/0,1`.
- `lib/wotex/ble/{uuid,address,peer,object_path,characteristic,value,procedure}.ex`:
  UUIDs, GATT targets, peer identity, D-Bus paths and scalar value codecs.
- `lib/wotex/ble/{client,session,port_call,subscription}.ex`: the client port,
  sessions and subscription handles.
- `lib/wotex/ble/bluez.ex` and `lib/wotex/ble/bluez/`: the BlueZ client, its
  persistent connection to the native host (`connection.ex`), artifact digest
  admission (`artifacts.ex`, `executable.ex`), bridge frames and replies
  (`frame.ex`, `response.ex`, `stream.ex`), the native report window
  (`report_flow.ex`), pairing (`pairing.ex`) and subscription owners.
- `lib/wotex/ble/{agent,challenge}.ex`: the consumer pairing decision boundary.
- `lib/wotex/ble/{mapping,transport,runtime_relay,runtime_frame}.ex`: Form
  mapping, the Runtime Transport and the relay that owns a persistent session
  for a Runtime subscription; `error.ex`: structured errors and Runtime classes.
- `lib/wotex/ble/native/`: the explicit native build (pinned libdbus source,
  command guardian, workspace and manifest); `lib/wotex/ble/software/`: the
  virtual-controller fixture build and run; `lib/mix/tasks/`: their Mix tasks.
- `priv/bluez/native/`: the C++17 host, C11 runtime guardian and command
  guardian sources, the vendored JSON header and the libdbus pin
  (`dependencies.json`).
- Specifications: `docs/packages/wotex-ble/specs/` (WBL.01–WBL.03,
  WBL.04–WBL.07; `catalogue.yaml` owns status). Plans and evidence:
  `docs/packages/wotex-ble/plans/` and `provenance/`.
- Fixtures: `priv/fixtures/` (contract, custody, native-port and integration
  corpora).
- Test support: `test/support/` (scripted clients, Runtime ports, native
  fixture compilation and lane selection, software peer configuration);
  `test/native/` (C/C++ component drivers and the native build image);
  `test/interop/native/` (command-guardian probes); `test/interop/virtual/`
  (virtual-controller images, guest scripts and the GATT peer).

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-ble test test/wotex/ble/<file>_test.exs`, or `mix impact Wotex.BLE.Module fun --run` |
| 1 | `mix check.fast --package wotex-ble` |
| 2 | `mix check` (full gate here) |

Native code (`priv/bluez/native/`, `test/native/`, `test/interop/native/`):
`mix native.lint --package wotex-ble` checks clang-format on the changed
lines (`--fix` formats them). The full gate adds `native_lint` (clang-tidy;
the D-Bus host and the bus test need the Linux libdbus build) and
`native_test` (on Linux, `test/interop/native_bus_test.exs` and
`native_host_test.exs` against that build; the other native tests run in
the ExUnit suite). On another host with Docker the Linux suite runs in the
Linux container of the native checks (`tooling/native/docker/linux.Dockerfile`);
without Docker it fails with a message.
`priv/bluez/native/vendor/` is never formatted or linted, and
`native_custody_test.exs` pins the digest of `custody.c`.

The full gate alone is `mix pkg wotex-ble check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-ble`); it adds
dependency audits, Doctor, docs, the 95% coverage floor, Dialyzer, the archive
check and the application-free check. Run `mix dialyzer.pkg wotex-ble` in tier
1 when a typespec, a client callback or an inferred return type changed. The
ordinary test run needs `cc` and `c++`.

Tests by area, under `test/wotex/ble/` unless noted:

- Values, identities and codecs: `identity_value_test.exs`,
  `characteristic_test.exs`, `procedure_test.exs`, `pairing_value_test.exs`,
  `stream_value_test.exs`, `bluez_test.exs`.
- Form mapping and the facade contract: `mapping_test.exs`, `contract_test.exs`,
  `contract_fixture_test.exs`, `port_test.exs`, `health_test.exs`.
- BlueZ bridge and persistent connection: `bluez_schema_test.exs`,
  `dbus_bridge_test.exs`, `stream_bridge_test.exs`,
  `stream_response_test.exs`, `report_flow_test.exs`,
  `native_process_flow_test.exs`, `native_startup_test.exs`,
  `native_artifacts_test.exs`.
- Native host components (compiled by the tests): `native_frame_test.exs`,
  `native_credit_test.exs`, `native_bytes_test.exs`, `native_output_test.exs`,
  `native_pages_test.exs`, `native_reports_test.exs`, `native_custody_test.exs`,
  `native_guardian_startup_test.exs`, `native_command_test.exs`,
  `native_contract_test.exs`.
- Native build and software fixture tasks: `native_build_test.exs`,
  `native_source_test.exs`, `software_fixture_test.exs`.
- Runtime integration, streams and error classes:
  `runtime_integration_test.exs`, `runtime_stream_test.exs`,
  `runtime_frame_test.exs`, `runtime_error_test.exs`.
- Locked Decimal parser boundary: `dependency_security_test.exs`.
- Package contents or `mix.exs` `package`: the full gate (archive check).

No sibling package depends on `wotex-ble`; it uses only the public APIs of
`wotex` and `wotex-runtime`. Consumers call its public API, so list callers
with `mix refs Wotex.BLE.Module fun` and the tests to run with
`mix impact Wotex.BLE.Module fun` before changing a public function.

Explicit-only lanes, never part of a bounded change. Each takes a disposable
absolute workspace; the README Development section lists their prerequisites.

```console
# Native build: Linux, cmake, ninja, pkg-config, cc, c++, readelf, xz, Expat headers, network
mix wotex.native.build --package wotex-ble --workspace /absolute/disposable/dir
# Sanitizer component lanes (leak_audit is Linux only)
WOTEX_BLE_NATIVE_LANE=sanitizers mix pkg wotex-ble test <native component test files>
# Built host and private bus (tag interop), against a completed native workspace
WOTEX_BLE_NATIVE_WORKSPACE=/absolute/disposable/dir \
  mix pkg wotex-ble test --only interop test/interop/native_host_test.exs
# BlueZ virtual controllers: Docker with linux/arm64, cc, network
mix pkg wotex-ble wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-ble wotex.software.run --workspace /absolute/disposable/dir
```

`test/interop/native_bus_test.exs` additionally needs `WOTEX_BLE_DBUS_SOURCE`
and `WOTEX_BLE_DBUS_BUILD` from a native workspace;
`test/interop/bluez_test.exs`, `test/interop/bluez_runtime_test.exs` and
`test/software/` run only inside the software lane;
`test/interop/bluez_device_test.exs` (tag `hardware`) needs
`WOTEX_BLE_BUSCTL` and `WOTEX_BLE_CHARACTERISTIC_PATH`. Apply the shared
`.claude/skills/spec-delivery/SKILL.md` for public behavior and standards
claims and `.claude/skills/release-readiness/SKILL.md` for compatibility
claims.
