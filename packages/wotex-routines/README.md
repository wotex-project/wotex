# Wotex Routines

Bounded, inert behaviour and observation values over installed Web of Things
capabilities. Consumers own device identity, policy, credentials, canonical
observations, clocks, persistence and effects.

The source currently provides explicit limits, offline contract closure,
behaviour basis, exact dimensional conversion, qualified-fact representation
and a lossless Continuum observation adapter, complete source compilation, qualified snapshot evaluation, retained composition transitions and continuous reported-edge qualification. Loading or constructing these
values starts no routine, network operation or timer. Complete provided-set evaluation and whole-resource arbitration are also implemented; UTC interval/one-shot and boot-scoped countdown calculation are implemented; the optional direct calendar adapter refuses unavailable producer capability; the explicitly started bounded wakeup driver is implemented; real host transactions, wider analysis models and consumer runtime adoption remain accepted successors; consult the
[catalogue](../../docs/packages/wotex-routines/specs/catalogue.yaml) for status.

Wotex Routines 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.18 through Elixir
1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).

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

The pure `Wotex.Routines.Kernel.advance/7` takes an explicit Event, complete Snapshot/Time and retained original/busy/edge slots. It returns inert proposals with their complete revalidation basis; the consumer persists originals and receipts, rechecks authority atomically and owns every handoff. Queue/protocol receipts never satisfy a higher installed report threshold. See the [source/kernel contract](../../docs/packages/wotex-routines/specs/WRO.02-source-kernel.md) and shipped `wro-02-*.schema.json` contracts.

Calendar consumers explicitly construct `Wotex.Routines.CalendarRequest` with a finite query and their immutable database module. ExBooking is pinned to optional `== 0.2.3`; its published archive lacks the occurrence API and returns unavailable. Our unreleased producer archive implements that generic API. The catalogue separates adapter code, actual archive adoption and host evidence. No availability interval supplies an original trigger.

`Wotex.Routines.AnalysisResult` keeps validity, findings, completion and admission separate. `Wotex.Routines.Witness.replay/4` checks a finite claimed counterexample against the pure kernel with explicit frames and retained originals. A nonviolating prefix supplies no universal safety proof; `Wotex.Routines.Model.compile/4` regenerates explicit frozen-time proposal and staged software-receipt projections. `Wotex.Routines.Analysis.run/5` runs the proposal-only profile with a complete expected binding, an explicit interpreter and a queue-inclusive monotonic deadline. ExMaude is optional and pinned to exact Hex 0.5.0. Wider models and OS containment remain separate obligations. See the [analysis contract](../../docs/packages/wotex-routines/specs/WRO.04-analysis-correspondence.md).

## Development

`InputMapping.new/3` checks a consumer-installed exact scalar correspondence.
`Input.project/4` joins a public Profiles proposal with explicit metadata and
registry/limits/reader_limits context into a Fact and witnesses. Mapping and
source/receipt clock mismatches refuse; no rounding, renewed freshness or effect
authority follows. The optional Profiles dependency can be absent during ordinary
routine use. See the [input contract](../../docs/packages/wotex-routines/specs/WRO.05-external-profile-inputs.md).

The [completion contract](../../docs/packages/wotex-routines/plans/wotex-routines-completion.md)
orders the accepted programme. From the repository root run focused tests with
`mix pkg wotex-routines test test/wotex/routines/basis_test.exs`, then
`mix check.fast --package wotex-routines`. The package gate adds archive,
application-free and boundary checks. Repository-wide expensive gates are
selected by the owning milestone and affected mechanisms.

## License

[Apache-2.0](LICENSE).
