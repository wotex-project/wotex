# Wotex Modbus package contract

Wotex Modbus (`packages/wotex-modbus`, Hex `wotex_modbus`) owns Modbus TCP
values, the codec and bounded protocol operations for functions 1, 2, 3, 4, 5,
6, 15 and 16 over an owned BEAM socket, Form mapping, the Runtime Transport and
a neutral compatibility adapter. Wotex core owns W3C Web of Things values and
Wotex Runtime owns interaction mechanics; consumers own policy, credentials,
supervision, connection configuration and canonical Property truth.
Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  application callback, framework integration or automatic network activity.
- Loading the dependency starts no process and performs no runtime filesystem
  access. Stateful transports start only through explicit calls or child
  specifications.
- Pure values never consult application environment, clocks or random sources.
  Transport time, identifiers, deadlines and ports have explicit ownership.
- Protocol execution is BEAM/OTP TCP; the libmodbus C peer is only an
  independent software peer under `test/interop/`. Build and test
  orchestration uses Mix/ExUnit. No Python runtime or target orchestration
  dependency is part of this contract.
- Never fetch remote JSON-LD contexts. Preserve unknown Form extensions.
- TD 1.1 is the baseline. Label binding drafts as drafts; a mapped Form proves
  neither authorization nor a physical effect.
- Errors are structured, input and allocation limits explicit, security modes
  fail closed, and write requests are never silently retried.
- Public functions have documentation and types. One module per `.ex` file.
  Test modules use `@moduledoc false` followed by a blank line.
- Consumer neutrality is a review obligation; never add a consumer denylist.

## Where things are

- `lib/wotex/modbus.ex`: the `Wotex.Modbus` facade: connect/disconnect,
  per-function and float helpers, `request/2`, compatibility callbacks and
  `profile/0`.
- `lib/wotex/modbus/{address,command,value}.ex`: validated register/coil
  ranges, function requests and exact-width scalar conversion.
- `lib/wotex/modbus/codec.ex`: MBAP/PDU encoding and function-specific
  response validation.
- `lib/wotex/modbus/{connection,session}.ex`: the owned TCP socket with
  bounded admission (64 requests, one active exchange) and deadline-bounded,
  correlated exchanges.
- `lib/wotex/modbus/mapping.ex`: Form mapping through the draft Modbus
  profile; `transport.ex`: the Runtime Transport.
- `lib/wotex/modbus/error.ex`: structured errors, effect and Runtime classes.
- `lib/mix/tasks/`: the explicit software-peer tasks; `bin/`: the
  candidate-archive and application-free checks run by the gate.
- Specifications: `docs/packages/wotex-modbus/specs/` (WMB.00–WMB.02,
  WMB.10–WMB.14; `catalogue.yaml` owns status). Plans and evidence:
  `docs/packages/wotex-modbus/plans/` and `provenance/`.
- Fixtures: `priv/fixtures/` (the contract corpus and the integration corpus).
- Test support: `test/support/` (loopback peer, contract and Runtime fixtures,
  Runtime credentials and transport, session trace);
  `test/support/software/` (software-lane runner, manifests and command
  guardian bindings); `test/interop/` (libmodbus peer, Dockerfiles and the
  POSIX command guardian).

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-modbus test test/wotex/modbus/<file>_test.exs`, or `mix impact Wotex.Modbus.Module fun --run` |
| 1 | `mix check.fast --package wotex-modbus` |
| 2 | `mix check.affected` (full gate here) |

The full gate alone is `mix pkg wotex-modbus check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-modbus`); it
adds dependency audits, Doctor, docs, the coverage floor, Dialyzer, the
candidate-archive consumer through a temporary signed Hex registry and the
application-free check. Run `mix dialyzer.pkg wotex-modbus` in tier 1 when a
typespec, a callback or an inferred return type changed. The ordinary test run
needs `cc`.

Tests by area, under `test/wotex/modbus/` unless noted:

- Codec, MBAP framing and function limits: `codec_test.exs`,
  `boundary_test.exs` (contract corpus), `stream_fault_test.exs`.
- Scalar conversion: `value_test.exs`.
- Form mapping: `mapping_test.exs`.
- Connection, helpers and compatibility callbacks: `connection_test.exs`,
  `compatibility_test.exs`, `contract_test.exs`.
- Admission, deadlines and owner cleanup: `lifecycle_test.exs`.
- Runtime integration and error classes: `runtime_integration_test.exs`.
- Telemetry metadata: `telemetry_test.exs`.
- Locked Decimal parser boundary: `dependency_security_test.exs`.
- Software-lane tasks and command guardian: `test/software/`.
- Package contents or `mix.exs` `package`: the full gate (archive check).

No sibling package depends on `wotex-modbus`; it uses only the public APIs of
`wotex` and `wotex-runtime`. Consumers call its public API, so list callers
with `mix refs Wotex.Modbus.Module fun` and the tests to run with
`mix impact Wotex.Modbus.Module fun` before changing a public function.

Explicit-only lanes, never part of a bounded change:

- The libmodbus software peer. It needs Docker, `cc`, `curl`, network access
  and a disposable absolute workspace outside the package; run it once per
  supported toolchain:

  ```console
  mix pkg wotex-modbus wotex.software.build --workspace /absolute/disposable/dir
  mix pkg wotex-modbus wotex.software.run --workspace /absolute/disposable/dir
  ```

  The `interop` and `software` tests run only inside that lane.
- The command guardian's Linux ASan/UBSan check, from `packages/wotex-modbus`:
  `docker build --tag wotex-modbus-guardian test/interop/native` then
  `docker run --rm wotex-modbus-guardian`.

There is no production native build. Apply the shared
`.claude/skills/spec-delivery/SKILL.md` for public behavior and standards
claims and `.claude/skills/release-readiness/SKILL.md` for compatibility
claims.
