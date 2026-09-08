# Executable evidence

Evidence collected 2026-09-08 using Elixir 1.20.2 / OTP 29.0.4.
Development contract supports Elixir 1.18+; the lower-version matrix has not been
executed in this workspace. Use CI before graduation. No consumer parity or
certification is inferred from unit coverage.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The reviewed Decimal advisory metadata exception and regression are documented
in SECURITY.md and the dependency-security test.

## Interoperability

NOT RUN: no SDK-backed controller driver or commissioned fixture was supplied.
No CASE/PASE, commissioning, ACL, attestation, subscription or device parity is
claimed. The mandatory tests use an explicitly selected test Client to check
contract failures and cleanup, plus TLV/path malformed-input and property tests.

The optional harness requires a compiled SDK driver implementing `Wotex.Matter.Client`.
Load that module on the test VM's code path, then set
`WOTEX_MATTER_CLIENT_MODULE=Elixir.YourControllerModule` and
`WOTEX_MATTER_FIXTURE=/absolute/fixture.json` when running
`mix test --include hardware test/interop/controller_test.exs`.
The fixture contains fabric_id, node_id, endpoint, cluster, member,
expected_value and unsupported_member; the driver receives the complete map in
its `:fixture` option. It must represent a real, isolated commissioned fixture.
Missing module/configuration or missing response fails instead of skipping.

Container source commits are pinned. Base-image/package-manager inputs may move;
these are reproducible source fixtures, not claims of bit-identical image builds.
Interoperability tags are excluded by default. Explicit invocation requires the
configured peer and must fail if that peer or expected response is missing.

## Evidence identities

The hashes identify reviewed test sources, not an immutable release or a promise
that all future test executions will pass. The mandatory gate and optional peer
commands above must be rerun after relevant changes.

| Test source | SHA-256 |
| --- | --- |
| `test/interop/controller_test.exs` | `aeb39cfbdf3c31935b7782faa347e9d25e96e25c01ff13171e7d145dac525c6e` |
| `test/wotex/matter/mapping_test.exs` | `41934eee1994453451d53d158253409b3d0220e5b69f7f6738c92bbfbac00369` |
| `test/wotex/matter/port_test.exs` | `933378f379e77c07c76e6b175a66adcf52d0616c0921b58f0aa136db52e5db90` |
| `test/wotex/matter/tlv_test.exs` | `eb245cee8ec6ae71543839d00b5faf2468c66a496c7e06695772a5dcab3fd242` |
