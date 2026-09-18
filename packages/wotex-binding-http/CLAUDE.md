# Wotex HTTP Binding package contract

Wotex HTTP Binding (`packages/wotex-binding-http`, Hex `wotex_binding_http`)
owns HTTP message mapping for selected Thing Description Forms and the
Server-Sent Events adaptation of `Wotex.Runtime.Transport`, both through a
consumer-supplied client port. Wotex core owns W3C Web of Things values and
terminology; Wotex Runtime owns interaction mechanics and subscription
supervision. Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- No database, Repo, migration, web framework, job framework, endpoint, global
  registry, application callback, built-in client, connection pool, credential
  store, or provider implementation.
- Loading starts no process. A stream opens only through the explicit Runtime
  subscription lifecycle and a supplied client port.
- HTTP request and response values never contain credentials. Credential
  material crosses only the immediate client-port call and must not be retained.
- Treat the current Profiles and Binding Registry documents as drafts. Never
  claim W3C Profile or registry conformance.
- One module per `.ex` file. Public functions have docs and types. Tests use
  `@moduledoc false` followed by a blank line.
- `bin/check_archive.exs` must keep rejecting Markdown documentation, agent
  files and `docs/tasks/local/` in every archive; create no tracker beneath
  publishable documentation.

## Where things are

- `lib/wotex/binding/http.ex`: public entry (`profile/0`, `config/1`,
  `transport/1`, `empty_body/0`).
- `lib/wotex/binding/http/client.ex`: the consumer client behaviour
  (`request/3`, `subscribe/4`, `close/2`), WBH.02.
- `lib/wotex/binding/http/form.ex`: internal Form and WoT operation to request
  mapping, default methods, `htv:methodName`, WBH.01.
- `lib/wotex/binding/http/transport.ex`: the Runtime transport callbacks,
  response validation, SSE open/close and `decode_frame/3`, WBH.01 and WBH.03.
- `lib/wotex/binding/http/{request,response,headers,codec,config,empty_body}.ex`:
  immutable credential-free values, field composition, bounded JSON and
  configuration limits, WBH.02.
- `lib/wotex/binding/http/{subscription,notification}.ex` and
  `sse/event.ex`: SSE handle, delivery metadata and framed event, WBH.03.
- `lib/wotex/binding/http/error.ex`: the classified, credential-free error.
- `bin/check_archive.exs`: three-archive build and reference consumer;
  `bin/check_boundary.exs`: the public-boundary scan.
- Specifications: `docs/packages/wotex-binding-http/specs/` (WBH.01 to WBH.03;
  `catalogue.yaml` owns status). Completion plan and the operation, lifecycle,
  limits, reference-consumer and release-candidate inventories are in
  `docs/packages/wotex-binding-http/`.
- Test support in `test/support/`: `factory.ex` (configs, requests),
  `fake_client.ex` and `alternate_client.ex` (scripted client ports),
  `fake_credentials.ex`. There are no fixture files.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-binding-http test test/wotex/binding/http/<file>_test.exs`, or `mix impact Wotex.Binding.HTTP.Transport request --run` |
| 1 | `mix check.fast --package wotex-binding-http` |
| 2 | `mix check.affected` (full gate here, fast gate in `wotex-lab`) |

The full gate alone is `mix pkg wotex-binding-http check --no-retry`
(equivalently `WOTEX_PATH_DEPS=1 mix check --no-retry` inside the package); it
adds dependency audits, Doctor, docs, the coverage floor, Dialyzer and the
exact-archive check. Run `mix dialyzer.pkg wotex-binding-http` in tier 1 when a
typespec, the client callbacks or an inferred return type changed.

Tests by area, all under `test/wotex/binding/http/`:

- Form and operation mapping, methods, input rules: `form_test.exs`,
  `operation_inventory_test.exs` (WBH-V vectors).
- Runtime transport, responses, SSE open/close, failure normalization:
  `transport_test.exs`.
- End-to-end through `Wotex.Runtime.ConsumedThing` and subscription
  processes: `integration_test.exs`.
- Client callback and lifecycle vectors: `client_lifecycle_inventory_test.exs`.
- Values, headers, configuration: `value_test.exs`; errors and retry classes:
  `error_test.exs`.
- Byte, field and URI limits, overload, redaction: `limits_security_test.exs`.
- Callback surfaces and passive load: `library_contract_test.exs`; locked
  Decimal boundary: `dependency_security_test.exs`.
- Package contents or `mix.exs` `package`: the full gate (archive check).

`wotex-lab` depends on this package (optionally) and implements its client
port in `Wotex.Lab.Adapters.HTTP.ReqClient`. This package calls the public API
of `wotex` and `wotex-runtime`. Before changing a public function or a client
callback, list callers with `mix refs Wotex.Binding.HTTP.Module fun` and the
tests to run with `mix impact Wotex.Binding.HTTP.Module fun`.

The boundary script is explicit-only: run `elixir bin/check_boundary.exs`
inside `packages/wotex-binding-http` before a commit that touches `lib/`,
`test/` or `mix.exs`. This package has no native build, software profile,
interop or container lane.
