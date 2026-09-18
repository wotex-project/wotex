# Wotex Runtime package contract

Wotex Runtime (`packages/wotex-runtime`, Hex `wotex_runtime`) owns
consumer-neutral interaction mechanics on top of the `wotex` values:
ConsumedThing and ExposedThing plans, deterministic Form and binding-profile
selection, the credential and transport ports, retry classification and
caller-supervised subscriptions. Wotex core owns the W3C Web of Things values
and terminology; this package inherits those types. Repository-wide rules are
in the root `CLAUDE.md`.

## Invariants

- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, endpoint, global
  registry, application callback, entitlement, or provider implementation.
- Loading starts no process. Short operations stay in the caller. A subscription
  starts only through an explicit caller-configured child specification.
- The caller supplies request identity, deadlines, credentials, transports,
  names, supervision, and policy decisions.
- A protocol result is not canonical Property truth or proof of an Action
  effect.
- One module per `.ex` file. Public functions have docs and types. Tests use
  `@moduledoc false` followed by a blank line.
- No mutable source selection. The normal `wotex` dependency is a released
  core version; `WOTEX_PATH_DEPS=1` selects `packages/wotex` for development
  only.
- Consumer neutrality is a review obligation governed by this contract; do not
  create a public denylist of private consumers.
- Package and archive checks must prove that `docs/` and the local tracker in
  `docs/tasks/local/wotex-runtime/` stay out of the archive.

## Where things are

- `lib/wotex/runtime.ex`: the TD 1.1 operation vocabulary (`operations/0`,
  `thing_operations/0`).
- `lib/wotex/runtime/consumed_thing.ex`: ConsumedThing construction, short
  operations and subscription child specifications (WRT.01, WRT.03).
- `lib/wotex/runtime/exposed_thing.ex`: handler dispatch by exact operation and
  affordance name (WRT.02).
- `lib/wotex/runtime/form_selector.ex`, `selection.ex`, `binding_profile.ex`:
  deterministic Form and binding-profile selection.
- `lib/wotex/runtime/transport.ex`, `credentials.ex`: the consumer ports;
  `port_call.ex` isolates raised callbacks; `execution_context.ex` carries
  credentials across one port call only.
- `lib/wotex/runtime/subscription.ex`, `subscription_opening.ex`: the
  caller-supervised observation and Event subscription process and its
  interruptible establishment.
- `lib/wotex/runtime/{context,request,result,error,limits}.ex`: request and
  result values, the stable error and fixed admission limits;
  `retry.ex`: pure retry classification; `telemetry.ex`: event names.
- `bin/check_package.exs`: archive and minimal-consumer check;
  `bin/check_reference_consumer.exs`: the RT-C04 reference consumer;
  `bin/check_boundary.exs`: the consumer-neutral source scan.
- Specifications: `docs/packages/wotex-runtime/specs/` (WRT.01 to WRT.03 and
  RT-C02 to RT-C06; `catalogue.yaml` owns status). Completion plan:
  `docs/packages/wotex-runtime/plans/wotex-runtime-completion.md`.
- Test support in `test/support/`: `TDFactory` builds Thing Descriptions,
  `FakeTransport` and `FakeCredentials` implement the ports, `OpeningPort`
  drives subscription establishment. There are no fixture files.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-runtime test test/wotex/runtime/<file>_test.exs`, or `mix impact Wotex.Runtime.ConsumedThing read_property --run` |
| 1 | `mix check.fast --package wotex-runtime` |
| 2 | `mix check` (full gate here, fast gate in every dependent) |

The full gate alone is `mix pkg wotex-runtime check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-runtime`); it
adds dependency audits, Doctor, docs, the coverage floor, Dialyzer, the boundary
scan and the archive check. Run `mix dialyzer.pkg wotex-runtime` in tier 1 when
a typespec, a port callback or an inferred return type changed.

Tests by area, all under `test/wotex/runtime/`:

- ConsumedThing construction, short operations, credential isolation, port
  errors and request telemetry: `consumed_thing_test.exs`.
- ExposedThing dispatch: `exposed_thing_test.exs`.
- Form and binding-profile selection, including top-level Forms:
  `form_selector_test.exs`.
- Subscription lifecycle, receiver death, overload and unsubscription:
  `subscription_test.exs`; establishment, handoff and early frames:
  `subscription_opening_test.exs`.
- Context, BindingProfile, Result and retry values: `value_test.exs`,
  `retry_test.exs`.
- Passive load, the `WOTEX_PATH_DEPS` switch and the operation vocabulary:
  `library_contract_test.exs`.
- Locked Decimal parser boundary: `dependency_security_test.exs`.
- Package contents or `mix.exs` `package`: the full gate (archive check).

Both bindings (`wotex-binding-http`, `wotex-binding-mqtt`), all seven protocol
adapters (`wotex-bacnet`, `wotex-ble`, `wotex-coap`, `wotex-matter`,
`wotex-modbus`, `wotex-opcua`, `wotex-thread`) and `wotex-lab` call this
package's public API; each implements `Wotex.Runtime.Transport` and returns
its request, result and error values. Before changing a public function or a port
callback, list its callers with `mix refs Wotex.Runtime.Module fun` and the
tests to run with `mix impact Wotex.Runtime.Module fun`.

Explicit-only lanes, run from `packages/wotex-runtime` with an exact core
archive: the RT-C04 reference consumer
(`WOTEX_CORE_ARCHIVE=/absolute/path/wotex-0.1.0.tar elixir bin/check_reference_consumer.exs`)
and the RT-C05 release-evidence commands listed in
`docs/packages/wotex-runtime/specs/RT-C05-release-evidence.md`. There is no
native build, software profile or container lane.
