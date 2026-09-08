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
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Interoperability

NOT RUN: no native SDK controller factory or commissioned fixture was supplied.
No CASE/PASE, commissioning, ACL, attestation, subscription or device parity is
claimed. The mandatory tests use an explicitly selected test Client to check
contract failures and cleanup, plus TLV/path malformed-input and property tests.

The optional harness can use the bundled `Wotex.Matter.SDK` adapter with an
installed native SDK and explicitly supplied Python controller factory. Its
fixture also needs executable, factory, settings and fabric_id. Alternatively,
load a custom Client module on the test VM code path. Set
`WOTEX_MATTER_CLIENT_MODULE=Elixir.Wotex.Matter.SDK` and
`WOTEX_MATTER_FIXTURE=/absolute/fixture.json` when running
`mix test --include hardware test/interop/controller_test.exs`.
The fixture contains fabric_id, node_id, endpoint, cluster, member,
expected_value and unsupported_member; the driver receives the complete map in
its `:fixture` option. It must represent a real, isolated commissioned fixture.
Missing module/configuration or missing response fails instead of skipping.
The default gate additionally executes five Python SDK API-contract tests.
Those use a deliberately selected test controller, not a native SDK session.

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
| `test/bridge/matter_bridge_test.py` | `f2f41e95a68180c117433d395221d4984683e333edddad2f325cdb49fd52422b` |
| `test/interop/controller_test.exs` | `06131cf65e51fc6992ed1df0d11aa4b31c27e8a2f803538c078eb8b3983cc6e4` |
| `test/wotex/matter/mapping_test.exs` | `41934eee1994453451d53d158253409b3d0220e5b69f7f6738c92bbfbac00369` |
| `test/wotex/matter/port_test.exs` | `933378f379e77c07c76e6b175a66adcf52d0616c0921b58f0aa136db52e5db90` |
| `test/wotex/matter/sdk_test.exs` | `b7699b283063ce3884b24fa5e39d55a5834c359872567d3a225c330ed33673ae` |
| `test/wotex/matter/tlv_test.exs` | `eb245cee8ec6ae71543839d00b5faf2468c66a496c7e06695772a5dcab3fd242` |
