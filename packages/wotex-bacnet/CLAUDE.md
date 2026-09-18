# Wotex BACnet package contract

Wotex BACnet (`packages/wotex-bacnet`, Hex `wotex_bacnet`) owns BACnet/IP
values, bounded protocol operations over the pinned BEAM BACstack client, COV
subscriptions, Who-Is discovery, Form mapping, the Runtime Transport and
observation relay, and a neutral compatibility adapter. Wotex core owns W3C Web
of Things values and Wotex Runtime owns interaction mechanics; consumers own
policy, credentials, supervision, connection configuration and canonical
Property truth. Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  application callback, framework integration or automatic network activity.
- Loading the dependency starts no process and performs no runtime filesystem
  access. Stateful transports start only through explicit calls or child
  specifications.
- Pure values never consult application environment, clocks or random sources.
  Transport time, identifiers, deadlines and ports have explicit ownership.
- The production client is Elixir/OTP over pinned BACstack 0.0.1, with no
  Python runtime, NIF or native executable. The BACnet C stack is only an
  independent software peer under `test/interop/`.
- Never fetch remote JSON-LD contexts. Preserve unknown Form extensions.
- TD 1.1 is the baseline. Label binding drafts as drafts; a mapped Form proves
  neither authorization nor a physical effect.
- Errors are structured, input and allocation limits explicit, security modes
  fail closed, and write requests are never silently retried.
- Public functions have documentation and types. One module per `.ex` file.
  Test modules use `@moduledoc false` followed by a blank line.
- Consumer neutrality is a review obligation; never add a consumer denylist.

## Where things are

- `lib/wotex/bacnet.ex`: the `Wotex.BACnet` facade: compatibility callbacks,
  native read/write/batch/discovery/COV helpers and `profile/0,1`.
- `lib/wotex/bacnet/{address,value,value_boundary,tags,character_string}.ex`:
  object/Property addresses and typed values with retained tags.
- `lib/wotex/bacnet/{client,session,port_call,native_call,operation_owner}.ex`:
  the consumer-selected client port, sessions and deadline-preserving calls.
- `lib/wotex/bacnet/ipv4*.ex`, `ingress_*.ex`, `stack_owner.ex`,
  `stack_client.ex`, `segments_store.ex`, `invoke_ids.ex`: the owned BACnet/IP
  stack with credit-bounded UDP ingress; `bacstack.ex` adapts a borrowed
  BACstack client.
- `lib/wotex/bacnet/cov*.ex`, `stack_cov.ex`, `native_subscription.ex`,
  `subscription.ex`: COV requests, registration, reports and cancellation.
- `lib/wotex/bacnet/{native_discovery,discovery_options,discovery_window,discovery_owner,device,batch,native_helpers}.ex`:
  Who-Is discovery and sequential Property batches.
- `lib/wotex/bacnet/{mapping,transport}.ex`, `runtime_*.ex`: Form mapping, the
  Runtime Transport and the relay that owns a native COV subscription for a
  Runtime observation; `error.ex`: structured errors and Runtime classes.
- `lib/mix/tasks/`: the explicit software-peer tasks; `bin/`: the archive and
  application-free checks run by the gate.
- Specifications: `docs/packages/wotex-bacnet/specs/` (WBA.01–WBA.03,
  WBA.04–WBA.06; `catalogue.yaml` owns status). Plans and evidence:
  `docs/packages/wotex-bacnet/plans/` and `provenance/`.
- Fixtures: `priv/fixtures/` (contract, ingress and integration corpora, pinned
  software sources); test-only corpora in `test/fixtures/`.
- Test support: `test/support/` (scripted clients, ports, transports and
  peers); `test/support/software/` (software-lane runner and manifests);
  `test/interop/` (C peer, Dockerfiles and the POSIX command guardian).

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-bacnet test test/wotex/bacnet/<file>_test.exs`, or `mix impact Wotex.BACnet.Module fun --run` |
| 1 | `mix check.fast --package wotex-bacnet` |
| 2 | `mix check` (full gate here) |

Native code (`test/interop/native/`, `test/interop/cstack/`): `mix
native.lint --package wotex-bacnet` checks clang-format on the changed lines
(`--fix` formats them). The full gate adds `native_lint` (clang-tidy; the C
stack peer against the pinned stack sources of `wotex.bacnet.software.build`,
which needs Docker) and `native_test` (the sanitized guardian check and the
peer's self-tests in its container).

The full gate alone is `mix pkg wotex-bacnet check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-bacnet`); it
adds dependency audits, Doctor, docs, the coverage floor, Dialyzer, the
exact-archive reference consumer and the application-free check. Run
`mix dialyzer.pkg wotex-bacnet` in tier 1 when a typespec, a client callback
or an inferred return type changed. The ordinary test run needs `cc`.

Tests by area, under `test/wotex/bacnet/` unless noted:

- Values, tags and character strings: `value_test.exs`,
  `character_string_test.exs`, `service_boundary_test.exs`.
- Form mapping and the facade contract: `mapping_test.exs`,
  `contract_test.exs`, `port_test.exs`, `standalone_contract_test.exs`,
  `health_probe_test.exs`.
- Owned stack, UDP ingress and sessions: `ipv4_test.exs`,
  `ipv4_packet_test.exs`, `ipv4_interface_test.exs`, `ingress_window_test.exs`,
  `ingress_lifecycle_test.exs`, `stack_lifecycle_test.exs`,
  `owned_session_test.exs`, `invoke_ids_test.exs`.
- Borrowed BACstack client: `bacstack_test.exs`, `bacstack_boundary_test.exs`.
- COV: `cov_test.exs`, `cov_cache_test.exs`, `cov_boundary_test.exs`,
  `cov_lifecycle_test.exs`, `stack_cov_test.exs`,
  `native_subscription_test.exs`.
- Discovery, batches and native helpers: `discovery_*_test.exs`,
  `batch_test.exs`, `native_helpers_test.exs`.
- Runtime integration, observations and error classes:
  `runtime_integration_test.exs`, `runtime_stream_test.exs`,
  `runtime_frame_test.exs`, `runtime_relay_test.exs`,
  `runtime_cov_mapping_test.exs`, `error_class_test.exs`.
- Locked Decimal parser boundary: `dependency_security_test.exs`.
- Software-lane tasks, manifests and command guardian: `test/software/`.
- Package contents or `mix.exs` `package`: the full gate (archive check).

No sibling package depends on `wotex-bacnet`; it uses only the public APIs of
`wotex` and `wotex-runtime`. Consumers call its public API, so list callers
with `mix refs Wotex.BACnet.Module fun` and the tests to run with
`mix impact Wotex.BACnet.Module fun` before changing a public function.

Explicit-only lane, never part of a bounded change: the independent C-stack
software peer. It needs Docker, `cc`, `curl`, network access and a disposable
absolute workspace outside the package:

```console
mix pkg wotex-bacnet wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-bacnet wotex.software.run --workspace /absolute/disposable/dir
```

The `interop`, `software` and `peer_shutdown` tests run only inside that lane.
There is no production native build. Apply the shared
`.claude/skills/spec-delivery/SKILL.md` for public behavior and standards
claims and `.claude/skills/release-readiness/SKILL.md` for compatibility
claims.
