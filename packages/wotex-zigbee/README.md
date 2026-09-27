# Wotex Zigbee

Wotex Zigbee 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through Elixir
1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).

Wotex Zigbee provides an explicit host boundary for a TI ZNP network
co-processor. It frames Monitor/Test serial traffic, negotiates the exact
firmware version, sends a small admitted set of ZDO and AF requests, and
delivers bounded asynchronous indications. It also encodes finite ZCL global
attribute reads and decodes attribute responses and reports.

The package does not form a Zigbee network, keep network keys, or infer a
device's physical state. Consumers supply hardware identity, network custody,
device profiles, policy and supervision. No process or serial port starts when
the package is loaded.

## Supported host profile

- TI CC26x2 SDK 2.30.00.34 ZNP interface and bundled Monitor/Test API
  SWRA198 revision 1.14, with 115200 baud, 8-N-1, optional RTS/CTS.
- Exact five-byte `SYS_VERSION` admission before a handle is returned.
- `ZDO_ACTIVE_EP_REQ`, `ZDO_SIMPLE_DESC_REQ` and `AF_DATA_REQUEST` with
  bounded payloads and one outstanding synchronous request.
- Separate asynchronous ZDO, AF confirmation and AF incoming events. Active
  endpoint and simple descriptor replies decode into typed, finite values.
  A successful synchronous reply proves NCP acceptance, not delivery.
- ZCL global Read Attributes encoding and bounded Read Attributes Response
  and Report Attributes decoding for catalogued scalar and short string types.
- `Wotex.Zigbee.DataRequest` keeps EUI-64 identity and caller correlation with
  a bounded AF request. Only the current route and ZNP-defined fields are
  transmitted; the consumer must verify IEEE-to-route custody after rejoin.

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
`Wotex.Zigbee.send_data/3`; keep the request to correlate later indications.
An immediate reply reports NCP admission only. Keys do not belong in this
request.

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
