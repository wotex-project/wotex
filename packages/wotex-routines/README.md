# Wotex Routines

Bounded, inert behaviour and observation values over installed Web of Things
capabilities. Consumers own device identity, policy, credentials, canonical
observations, clocks, persistence and effects.

The source currently provides explicit limits, offline contract closure,
behaviour basis, exact dimensional conversion, qualified-fact representation
and a lossless Continuum observation adapter. Loading or constructing these
values starts no routine, network operation or timer. The pure source/kernel,
temporal driver and analysis contracts are accepted successors; consult the
[catalogue](../../docs/packages/wotex-routines/specs/catalogue.yaml) for status.

## Consumption

The family is unpublished. Follow the repository's
[pinned-source instructions](https://github.com/wotex-project/wotex#using-wotex)
or consume a coherent exact archive cohort. All siblings must be selected
explicitly; development path dependencies are not released-artifact evidence.
Supported family lanes run Elixir 1.18.4/OTP 27 through Elixir 1.20.2/OTP 29.

Start with the complete caller-selected Limits map. Every constructor returns
an accepted immutable value or a payload-free Error with code and JSON Pointer.
There is no default registry, clock or rounding policy. Basis construction
requires the exact installed contract closure; changing a proposal digest does
not install its meaning. Unit conversion requires equal dimensions and an
exact in-domain integer result. Unknown observations retain null/quality and
never become false or zero.

The [behaviour contract](../../docs/packages/wotex-routines/specs/WRO.01-capability-behaviour.md)
contains every required member and the Continuum field mapping. The shipped
schema is `priv/schemas/wro-01.schema.json`; independent scalar, event, fast/slow
actuator and media examples and hand-calculated conversions are in
`priv/vectors/wro-01.json`. They are software fixtures, not device qualification.
Checked projections revalidate caller-built structs against explicit limits.

## Development

The [completion contract](../../docs/packages/wotex-routines/plans/wotex-routines-completion.md)
orders the accepted programme. From the repository root run focused tests with
`mix pkg wotex-routines test test/wotex/routines/basis_test.exs`, then
`mix check.fast --package wotex-routines`. The package gate adds archive,
application-free and boundary checks. Repository-wide expensive gates are
selected by the owning milestone and affected mechanisms.

## License

[Apache-2.0](LICENSE).
