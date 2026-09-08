# Wotex Modbus

Consumer-neutral Modbus protocol library for W3C Web of Things consumers.
Development version: API unstable; no certification or complete protocol
conformance claim. No remote repository or published package is implied.

## Ownership

Values, validation and Form mapping belong here. The consumer owns credentials,
policy, supervision and the interpretation of protocol acknowledgements.
Loading the package does not start a transport. No simulator is selected implicitly.

## Development

Use Elixir 1.18 or newer and an appropriate OTP release. To use local Wotex core
and Runtime checkouts, run `WOTEX_PATH_DEPS=1 mix deps.get` then
`WOTEX_PATH_DEPS=1 mix check`. Normal dependency resolution uses Hex versions.
Optional interoperability suites run only on explicit invocation and must fail
when their configured peer is missing or returns no response.

See [delivery contract](docs/plans/wotex-modbus-completion.md).

## Implemented profile

Classic Modbus TCP functions 1, 2, 3, 4, 5, 6, 15 and 16; strict MBAP/response
validation; integer/float register conversion; explicit socket ownership;
WoT Forms and Runtime requests; neutral compatibility callbacks.

```elixir
{:ok, session} = Wotex.Modbus.connect(host: "127.0.0.1", port: 1502, unit_id: 1)
try do
  Wotex.Modbus.read_holding_registers(session, 0, 2)
after
  Wotex.Modbus.disconnect(session)
end
```

No RTU/serial, Modbus Security, built-in polling or physical certification is
claimed. See [protocol contract](docs/specs/WMB.01-protocol.md),
[Form profile](docs/specs/WMB.02-form-profile.md) and
[independent interoperability](test/interop/README.md).
