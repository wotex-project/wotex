# Wotex Zigbee

Wotex Zigbee 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.18 through Elixir
1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).

Wotex Zigbee provides an explicit host boundary for a TI ZNP network
co-processor. It frames Monitor/Test serial traffic, negotiates the exact
firmware version, sends a small admitted set of ZDO and AF requests, and
delivers bounded asynchronous indications. It also encodes finite ZCL global
attribute reads, writes and reporting configuration, and decodes their
responses and attribute reports.

The package does not form a Zigbee network, keep network keys, or infer a
device's physical state. Consumers supply hardware identity, network custody,
device profiles, policy and supervision. No process or serial port starts when
the package is loaded.

## Supported host profile

- TI CC26x2 SDK 2.30.00.34 ZNP interface and bundled Monitor/Test API
  SWRA198 revision 1.14, with 115200 baud, 8-N-1, optional RTS/CTS.
- Exact five-byte `SYS_VERSION` admission before a handle is returned.
- `ZDO_IEEE_ADDR_REQ`, `ZDO_NODE_DESC_REQ`, `ZDO_ACTIVE_EP_REQ`,
  `ZDO_SIMPLE_DESC_REQ` and `AF_DATA_REQUEST` with
  bounded payloads and one outstanding synchronous request.
- Separate asynchronous ZDO, AF confirmation and AF incoming events. Active
  endpoint, IEEE identity, node and simple descriptor replies decode into
  typed, finite values pinned to the selected Monitor/Test revision.
  A successful synchronous reply proves NCP acceptance, not delivery.
- ZCL global Read Attributes encoding and bounded Read Attributes Response
  and Report Attributes decoding for catalogued scalar and short string types.
  Revision 8 non-values remain null with their original bytes; full-range
  numeric attribute definitions require explicit decoder policy.
- Inert ordinary Write Attributes, Configure Reporting and Read Reporting
  Configuration requests with bounded scalar values and explicit intervals.
  Source-matched responses preserve per-record outcomes and raw evidence.
- `Wotex.Zigbee.interview/3` matches expected IEEE identity, node and endpoint
  descriptors, then reads selected Basic attributes under one overall deadline.
  The Basic read selection is pinned to ZCL document 07-5123 revision 8.
  Ordered results retain partial issues and distinct NCP/APS/ZCL observations.
- `Wotex.Zigbee.DataRequest` keeps EUI-64 identity and caller correlation with
  a bounded AF request. Only the current route and ZNP-defined fields are
  transmitted.
- `Wotex.Zigbee.Routes` explicitly adopts complete interviews into a bounded
  consumer-owned IEEE ledger. Guarded AF sends and source resolution check
  epoch, custody expiry and route; rejoin and conflicts stay visible.

`Wotex.Zigbee.Serial.CircuitsUART` is the included macOS/Linux serial adapter.
It uses `Circuits.UART` and requires the coordinator's USB serial number,
vendor ID and product ID. It refuses missing or ambiguous identities and
rechecks the selected port after opening. Nerves targets can use the same
adapter when their serial driver and USB metadata are available. The consumer
still supplies and qualifies the exact NCP firmware; no firmware ships here.

```elixir
{:ok, config} =
  Wotex.Zigbee.Config.new(
    serial: Wotex.Zigbee.Serial.CircuitsUART,
    device_id: "coordinator-usb-serial-number",
    expected_version: {2, 0, 3, 2, 0},
    serial_options: [vendor_id: 0x0451, product_id: 0x16A8]
  )

{:ok, handle} = Wotex.Zigbee.open(config)
{:ok, admission} = Wotex.Zigbee.active_endpoints(handle, 0x1234, 1_000)
{:ok, %{events: events, dropped: dropped}} = Wotex.Zigbee.drain_events(handle, 32)
:ok = Wotex.Zigbee.close(handle)
```

The identity, USB IDs and version tuple above are illustrative. Configure the
exact values of the selected device and firmware. The network address in the
example is a transient route, not durable device identity. The adapter does
not create a network or reconnect automatically after USB loss.

For AF traffic, construct `Wotex.Zigbee.DataRequest` with an interviewed
eight-byte peer IEEE address, current `route_address`, endpoints, cluster,
transaction, opaque `correlation_id` and finite `data`. Pass it to
`Wotex.Zigbee.send_routed_data/4` with the current adopted route table; keep
the request to correlate later indications. An immediate reply reports NCP
admission only. Keys do not belong in this request. `send_data/3` remains
available when the consumer separately enforces route custody.

`Wotex.Zigbee.ieee_address/3` and `node_descriptor/3` query a known unicast
route under a finite timeout. Drain their later typed Events separately from
NCP admission and correlate them under the consumer's interview policy.
IEEE bytes and descriptor claims do not authenticate a device. The owner
refuses undeclared or modified command frames before serial I/O and invalidates
its epoch on a malformed synchronous response.

For a full bounded inspection, construct `Wotex.Zigbee.Interview` with
`peer_ieee`, `route_address` and an already registered `source_endpoint`, then
call `Wotex.Zigbee.interview/3`. The default admits at most 16 advertised
endpoints and selects ZCLVersion, ManufacturerName, ModelIdentifier and
ClusterRevision from eligible Basic servers. Duplicate lists and attribute
records stay visible. Unrelated indications remain in the ordinary event
queue. A partial result identifies failed or unavailable stages without
retrying, joining or configuring the device.

After reviewing a complete result, use `Wotex.Zigbee.Routes.new/2` with its
`owner_epoch` and `Routes.adopt/4` with the result, monotonic milliseconds and
a finite lifetime. The lifetime begins at the identity observation, not at
adoption. Retain the latest returned table, including the third element of
`{:error, error, table}` when adoption quarantines a route conflict. A newer
interview can replace the same IEEE's route. Forgetting one conflicting peer
does not make another claim current.

`Routes.resolve/3` returns the unchanged Event alongside its current peer
record. It checks owner epoch, expiry and observation ordering; it does not
authenticate a report or upgrade the NCP security flag. When replacing an
owner, call `Routes.rebind/2` and obtain a fresh interview before using retained
routes. Supply the current table to guarded sends: old immutable snapshots
cannot observe later consumer decisions. Custody expiry does not declare a
sleepy device offline.

`Wotex.Zigbee.ZCL.decode_attributes/3` distinguishes failed read status,
standard non-value (`:null`), ordinary value and unsupported type. It retains
original bytes for successful records. Its third argument selects numeric
attribute IDs whose adopted cluster/manufacturer definition uses the full
range, including the otherwise reserved encoding. Keep that policy explicit;
the codec does not infer device semantics. Unsupported widths retain the
remaining opaque payload without guessing later record boundaries.

For an explicitly authorized write or reporting change, use
`Wotex.Zigbee.ZCL.Configuration.write_attributes/4`,
`configure_reporting/4` or `read_reporting/4`. Each returns an inert request
with `payload` for a `DataRequest`. Retain both values, send through the
current route table, and use `Configuration.observe/5` with the later source
Event and monotonic milliseconds. It checks payload, custody, endpoints,
cluster and ZCL header context and returns ordered peer-reported outcomes.
Retain actual dispatch, NCP admission and APS confirmation separately. The
consumer owns a finite correlation window and distinct transaction/sequence
context; matching alone does not establish dispatch or prevent replay.

Configure-send records specify `report_direction: :send`, `id`, `type`,
`min_interval_s` and `max_interval_s`, plus integer `change` for analog types.
Configure-receive records specify `report_direction: :receive`, `id` and
`timeout_s`. Maximum `0xFFFF` disables reporting; minimum `0xFFFF` with maximum
zero restores defaults. Both modes require analog change zero. Ordinary
maximum zero retains change-based reporting. Binding destinations, cluster
limits and battery policy belong to the consumer. A Default Response leaves
records unconfirmed, even with success status. Inspect partial issues before
accepting outcomes; construction and observation never retry or bind.

An interview needs a route with no earlier ZDO query in that owner epoch.
The owner retains at most 128 queried routes and retires Basic transaction
and sequence bytes from a 256-byte window. Reuse or exhaustion is explicit;
consumers may negotiate a new serial owner without resetting the network.
Timeout after dispatch or caller death closes the owner. Serial adapter
callbacks must return within the operation budget; the owner cannot preempt
a blocking callback. Consumer table ownership, authorization and physical
firmware/endpoint qualification remain separate.

Startup shares one deadline across serial open, version write and negotiation.
A late port is closed before requesting the version, and a late reply cannot
produce a handle. A shorter `Owner.ready/2` wait can shorten that budget.
Negotiating caller loss ends ownership. Open/write/close callback faults
become redacted errors. An acquired port receives one close attempt; explicit
close reports a serial error when the adapter does not acknowledge cleanup.
An adapter that fails before returning a port owns its own acquired resources.

## Development

Run commands from the repository root:

```console
mix pkg wotex-zigbee test test/wotex/zigbee/owner_test.exs
mix check.fast --package wotex-zigbee
mix pkg wotex-zigbee check --no-retry
mix bench --package wotex-zigbee
```

The [specification catalogue](../../docs/packages/wotex-zigbee/specs/catalogue.yaml)
records the implemented and outstanding portions of WZG.01–WZG.03. The
[completion plan](../../docs/packages/wotex-zigbee/plans/wotex-zigbee-completion.md)
describes the remaining network and hardware evidence.

## License

Apache-2.0. The package archive includes the license text.
