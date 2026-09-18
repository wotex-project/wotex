# Wotex package contract

Wotex (`packages/wotex`, Hex `wotex`) owns consumer-neutral W3C Web of Things
values: Thing Description 1.1 and Thing Model 1.1 parsing, validation,
extension preservation and deterministic encoding, and the DataSchema, Form,
Interaction Affordance and security-scheme values the rest of the family
builds on. Consumers inherit these public values and must not cause this
package to import their product models or redefine the standard terms.
Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, endpoint, queue,
  PubSub, entitlement, provider implementation, or application callback.
- Loading the dependency starts no process and performs no network or runtime
  filesystem access.
- Remote JSON-LD contexts are never fetched.
- One module per `.ex` file. Tests use `@moduledoc false` followed by a blank
  line. Public functions have types and documentation.
- Preserve unknown extension terms. Never validate consumer-specific extension
  meaning as W3C behavior.
- Keep maps immutable, errors structured, limits explicit, and output
  deterministic where claimed.
- Consumer neutrality is a review obligation governed by this contract; do not
  create a public denylist of private consumers.

## Where things are

- `lib/wotex.ex`: context and media-type constants (`td_context_1_1/0`,
  `td_media_type/0`, `tm_media_type/0`).
- `lib/wotex/thing_description.ex`: the Thing Description aggregate (parse,
  `from_map`, validate, `put_id`, encode); semantic checks in
  `thing_description/validator.ex` and `security_references.ex` (WTX.01).
- `lib/wotex/thing_model.ex`: the separate Thing Model aggregate; checks in
  `thing_model/validator.ex` and `model_references.ex` (WTX.04).
- `lib/wotex/{data_schema,form,property_affordance,action_affordance,event_affordance,security_scheme}.ex`:
  immutable value modules (WTX.02); shared construction in `value.ex`, schema
  fragments in `value_schema.ex`.
- `lib/wotex/json.ex`, `lib/wotex/json/limits.ex`: bounded JSON admission,
  resource limits and canonical encoding.
- `lib/wotex/error.ex`: the structured error (WTX.03).
- `priv/w3c/`: the pinned TD and Thing Model informative schemas, the W3C
  license and local modifications; provenance in
  `docs/packages/wotex/provenance/`.
- `bin/check_package.exs`: archive and minimal-consumer check;
  `bin/wcf_target.exs`: the WCF target adapter for the reference corpus;
  `bin/check_boundary.exs`: the consumer-neutral source scan.
- Specifications: `docs/packages/wotex/specs/` (WTX.01 to WTX.04;
  `catalogue.yaml` owns status). Completion plan:
  `docs/packages/wotex/plans/wotex-completion.md`. Tests build their documents
  inline; there are no fixture files and no `test/support/`.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex test test/wotex/<file>_test.exs`, or `mix impact Wotex.ThingDescription parse --run` |
| 1 | `mix check.fast --package wotex` |
| 2 | `mix check` (full gate here, fast gate in every dependent) |

The full gate alone is `mix pkg wotex check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex`); it adds
dependency audits, Doctor, docs, the coverage floor, Dialyzer, the boundary scan
and the archive check. Run `mix dialyzer.pkg wotex` in tier 1 when a typespec or
inferred return type changed.

Tests by area, all under `test/wotex/`:

- Thing Description parsing, validation, encoding: `thing_description_test.exs`.
- Thing Model: `thing_model_test.exs`.
- DataSchema, Form, affordance and security-scheme values: `value_test.exs`.
- JSON admission, limits, canonical encoding: `json_test.exs`.
- Unicode, byte/depth/node bounds, option containers, source invalidation
  (WTX-C02): `admission_safety_test.exs`.
- Constants and passive load: `library_contract_test.exs`.
- Locked Decimal parser boundary: `dependency_security_test.exs`.
- Package contents, `priv/w3c/` or `mix.exs` `package`: the full gate
  (archive check).

Every package except `wotex-conformance` depends on Wotex: `wotex-runtime`,
`wotex-directory`, `wotex-nx`, `wotex-continuum`, both bindings, all seven
protocol adapters and `wotex-lab`. Before changing a public function, list its
callers with `mix refs Wotex.Module fun` and the tests to run with
`mix impact Wotex.Module fun`. A changed public signature needs the gates of
the dependents that call it.

Wotex has no native build, software profile or container lane. The
reference-corpus evidence (`docs/packages/wotex/provenance/reference-corpus.md`)
drives `bin/wcf_target.exs` against the unpacked archive; re-record it only
when asked.
