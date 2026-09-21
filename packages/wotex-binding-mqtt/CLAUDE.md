# Wotex MQTT Binding package contract

Wotex MQTT Binding (`packages/wotex-binding-mqtt`, Hex `wotex_binding_mqtt`)
owns only the MQTT binding values, the mapping of MQTT Forms to immutable
commands, the JSON payload boundary, and the process-free
`Wotex.Runtime.Transport` adapter around a consumer-supplied client port. Wotex
core owns W3C Web of Things values and terminology; Wotex Runtime owns
interaction mechanics. Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- Do not add an OTP Application callback, process, supervisor, connection
  manager, MQTT client implementation, database, or framework dependency.
- The consumer supplies the MQTT client port, its connection ownership, policy,
  deadlines, credentials, and supervision.
- Commands, broker values, errors, delivery values, and package configuration
  remain immutable and credential-free. Credentials cross only an immediate
  client-port call through `Wotex.Runtime.ExecutionContext`.
- Preserve the exact `mqv:retain`, `mqv:controlPacket`, `mqv:qos`, `mqv:topic`,
  and `mqv:filter` terms from the dated editor's draft. Do not put a topic or
  filter in the broker href.
- Do not claim W3C conformance. The referenced MQTT binding and Binding Registry
  remain works in progress at the documented observation date.
- One module per `.ex` file. Public functions have docs and types. Test modules
  use `@moduledoc false` followed by a blank line.
- `bin/check_archive.exs` must require `usage-rules.md` while rejecting the
  documentation tree, other Markdown documentation, repository agent files
  and `docs/tasks/local/`; create no tracker beneath publishable
  documentation.

## Where things are

- `lib/wotex/binding/mqtt.ex`: public entry and Runtime binding profile
  (`profile/0`).
- `lib/wotex/binding/mqtt/client.ex`: the consumer client behaviour
  (`publish/3`, `read/4`, `subscribe/4`, `unsubscribe/4`), WBM.01.
- `lib/wotex/binding/mqtt/mapping.ex`: Form and WoT operation to Control
  Packet mapping and defaults, WBM.02.
- `lib/wotex/binding/mqtt/transport.ex` and `transport_config.ex`: the Runtime
  transport callbacks, retained reads, subscription open/close and
  `decode_frame/3`, WBM.03.
- `lib/wotex/binding/mqtt/{broker,command,delivery,topic,qos,json}.ex`:
  immutable broker, command and delivery values, Topic Name/Filter and QoS
  validation, bounded JSON, WBM.01.
- `lib/wotex/binding/mqtt/error.ex`: the classified, credential-free error.
- `bin/check_archive.exs`: three-archive build and reference consumer;
  `bin/check_application_free.exs`: no application module;
  `bin/check_boundary.exs`: the public-boundary scan.
- Specifications: `docs/packages/wotex-binding-mqtt/specs/` (WBM.01 to WBM.03
  and the WBM-C01 to WBM-C03 completion packets; `catalogue.yaml` owns status).
  Completion plan, inventories and runtime baseline are in
  `docs/packages/wotex-binding-mqtt/`; dated draft and source provenance in its
  `provenance/`.
- Test support in `test/support/`: `request_factory.ex` and `td_factory.ex`
  (Runtime requests, Thing Descriptions), `fake_client.ex` and
  `lifecycle_client.ex` (scripted client ports), `fake_credentials.ex`. There
  are no fixture files.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-binding-mqtt test test/wotex/binding/mqtt/<file>_test.exs`, or `mix impact Wotex.Binding.MQTT.Mapping command --run` |
| 1 | `mix check.fast --package wotex-binding-mqtt` |
| 2 | `mix check` (full gate here, fast gate in `wotex-lab`) |

The full gate alone is `mix pkg wotex-binding-mqtt check --no-retry`
(equivalently `WOTEX_PATH_DEPS=1 mix check --no-retry` inside the package); it
adds dependency audits, Doctor, docs, the coverage floor, Dialyzer, the
boundary scan, the exact-archive check and the application-free check. Run
`mix dialyzer.pkg wotex-binding-mqtt` in tier 1 when a typespec, the client
callbacks or an inferred return type changed.

Tests by area, all under `test/wotex/binding/mqtt/`:

- Form mapping and the seven-row operation inventory (WBM-C01):
  `mapping_test.exs`, `operation_inventory_test.exs`.
- Values: `broker_test.exs`, `command_test.exs`, `delivery_test.exs`,
  `topic_test.exs`, `qos_test.exs`, `json_test.exs`,
  `transport_config_test.exs`.
- Runtime transport, publish, retained read, failure normalization:
  `transport_test.exs`; subscriptions through Runtime:
  `runtime_subscription_test.exs`.
- Client timeouts, handles, close failures, restart (WBM-C02):
  `client_lifecycle_test.exs`.
- Thresholds, filter cardinality, overload, redaction (WBM-C03):
  `limits_security_test.exs`.
- Profile and no application module: `library_contract_test.exs`; locked
  Decimal boundary: `dependency_security_test.exs`.
- Package contents or `mix.exs` `package`: the full gate (archive check).

`wotex-lab` depends on this package (optionally) and implements its client
port in `Wotex.Lab.Adapters.MQTT.EmqttClient`. This package calls the public
API of `wotex` and `wotex-runtime`. Before changing a public function or a
client callback, list callers with `mix refs Wotex.Binding.MQTT.Module fun` and
the tests to run with `mix impact Wotex.Binding.MQTT.Module fun`.

The full gate runs the boundary scan; run it alone with
`elixir bin/check_boundary.exs` inside `packages/wotex-binding-mqtt` after
touching `lib/`, `test/` or `mix.exs`. No test needs a broker; this package has
no native build, software profile, interop or container lane.
