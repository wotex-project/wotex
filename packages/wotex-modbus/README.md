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
