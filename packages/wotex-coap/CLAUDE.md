# Wotex CoAP package contract

Wotex CoAP (`packages/wotex-coap`, Hex `wotex_coap`) owns CoAP values and
codecs, bounded UDP, DTLS and native OSCORE exchanges, blockwise transfer,
Observe, CoRE Link Format discovery, Form mapping, the Runtime Transport and
observation relay, the explicitly built native OSCORE helper and a neutral
compatibility adapter. Wotex core owns W3C Web of Things values and Wotex
Runtime owns interaction mechanics; consumers own policy, credentials,
supervision, connection configuration and canonical Property truth.
Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  application callback, framework integration or automatic network activity.
- Loading the dependency starts no process and performs no runtime filesystem
  access. Stateful transports start only through explicit calls or child
  specifications. Dependency loading and `mix compile` never build or launch
  the native helper.
- Pure values never consult application environment, clocks or random sources.
  Transport time, identifiers, deadlines and ports have explicit ownership.
- Native protocol execution uses BEAM/OTP and the explicitly specified native
  SDK Port. Build and test orchestration uses Mix/ExUnit; no Python runtime or
  target orchestration dependency is part of this contract.
- Never fetch remote JSON-LD contexts. Preserve unknown Form extensions.
- TD 1.1 is the baseline. Label binding drafts as drafts; a mapped Form proves
  neither authorization nor a physical effect.
- Errors are structured, input and allocation limits explicit, security modes
  fail closed, and write requests are never silently retried.
- Public functions have documentation and types. One module per `.ex` file.
  Test modules use `@moduledoc false` followed by a blank line.
- Consumer neutrality is a review obligation; never add a consumer denylist.

## Where things are

- `lib/wotex/coap.ex`: the `Wotex.CoAP` facade: compatibility callbacks,
  method helpers, discovery, Observe and `profile/0,1`.
- `lib/wotex/coap/{message,codec,block,observe}.ex`: RFC 7252 messages and
  codec, Block1/Block2 options and Observe freshness as pure values.
- `lib/wotex/coap/{connection,exchange,execution,lifetime,blockwise}.ex`,
  `datagram.ex`, `datagram/{udp,dtls}.ex`: the owned connection, bounded
  exchanges and retransmission, whole-body transfer and the UDP and OTP DTLS
  datagram owners.
- `lib/wotex/coap/{observation,subscription,subscription_inspect}.ex`,
  `observation/report.ex`: native Observe registration, reports and
  cancellation.
- `lib/wotex/coap/link_format.ex`, `link_format/attribute.ex`: CoRE Link
  Format discovery values.
- `lib/wotex/coap/security.ex`, `security/{pki,peer,crl_cache}.ex`: DTLS PSK
  and PKI and OSCORE credential values and the OTP certificate policy.
- `lib/wotex/coap/{mapping,transport}.ex`, `runtime_*.ex`: Form mapping, the
  Runtime Transport, route security and the relay that owns a native Observe
  for a Runtime subscription; `error.ex`: structured errors and Runtime
  classes.
- `lib/wotex/coap/native_backend.ex`, `native/{connection,admission,command,wire,body,report,report_ledger}.ex`:
  verification and ownership of the native OSCORE helper and its bounded
  JSON-line protocol.
- `lib/wotex/coap/native/{build,build_command,build_operations,toolchain,workspace,archive}.ex`,
  `software/{build,run}.ex`, `lib/mix/tasks/`: the explicit native build and
  software-lane tasks.
- `native/oscore/`: the C helper (worker, exchange, observation, custody,
  store), vendored yyjson, the libcoap source pin (`source.json`) and ordered
  patches.
- Specifications: `docs/packages/wotex-coap/specs/` (WCO.00–WCO.03,
  WCO.10–WCO.13; `catalogue.yaml` owns status). Plans and evidence:
  `docs/packages/wotex-coap/plans/` and `provenance/`.
- Fixtures: `priv/fixtures/` (contract, custody, native and integration
  corpora); DTLS PKI material in `test/fixtures/dtls_pki/`
  (`bin/generate_dtls_pki.exs` regenerates it).
- Test support: `test/support/` (datagram and Runtime fixtures, libcoap,
  OSCORE and Californium peers, DTLS record proxy); `test/native/` (C
  harnesses and sanitizer Dockerfiles); `test/interop/` and `test/software/`
  (explicit-lane suites).

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-coap test test/wotex/coap/<file>_test.exs`, or `mix impact Wotex.CoAP.Module fun --run` |
| 1 | `mix check.fast --package wotex-coap` |
| 2 | `mix check.affected` (full gate here) |

The full gate alone is `mix pkg wotex-coap check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-coap`); it
adds dependency audits, Doctor, docs, the 95% coverage floor, Dialyzer, the
out-of-tree archive compilation and the application-free check. Run
`mix dialyzer.pkg wotex-coap` in tier 1 when a typespec, a callback or an
inferred return type changed. The default suite needs a supported
native-build host (Linux x86-64/AArch64 or macOS AArch64) with the complete
native toolchain on the `PATH`: `cc`, `cmake`, `curl`, `openssl`, `patch`,
`pkg-config` with OpenSSL development files, and `ldd` or `otool`.

Tests by area, under `test/wotex/coap/` unless noted:

- Messages, codec and datagram owners: `codec_test.exs`, `datagram_test.exs`.
- Connection, exchanges and deadlines: `connection_test.exs`,
  `exchange_lifecycle_test.exs`, `exchange_deadline_test.exs`,
  `execution_test.exs`.
- Blockwise transfer: `blockwise_test.exs`.
- Observe: `observation_test.exs`, `observation_lifecycle_test.exs`,
  `observation_value_test.exs`, `observation_trace_test.exs`.
- Discovery and Link Format: `discovery_test.exs`, `link_format_test.exs`.
- DTLS and credentials: `dtls_test.exs`, `dtls_pki_test.exs`,
  `security_test.exs`, `security_pki_test.exs`, `security_callbacks_test.exs`,
  `security_oscore_test.exs`, `test_oscore_vectors_test.exs`.
- Form mapping, profiles and the facade contract: `mapping_test.exs`,
  `profile_test.exs`, `contract_test.exs`, `native_contract_test.exs`.
- Runtime integration and error classes: `runtime_stream_test.exs`,
  `runtime_owner_test.exs`, `runtime_dtls_test.exs`, `runtime_oscore_test.exs`,
  `runtime_error_test.exs`.
- Native helper protocol and ownership: `native_backend_test.exs`,
  `native_connection_test.exs`, `native_admission_test.exs`,
  `native_command_encoder_test.exs`, `native_wire_test.exs`,
  `native_body_test.exs`, `native_report_test.exs`,
  `native_report_ledger_test.exs`, `native_worker_test.exs`,
  `native/custody_test.exs`.
- Native build and software-lane tasks: `native_build_test.exs`,
  `native_build_command_test.exs`, `native_toolchain_test.exs`,
  `native_workspace_test.exs`, `native_archive_test.exs`,
  `software_build_test.exs`, `software_run_test.exs`.
- Locked Decimal parser boundary: `dependency_security_test.exs`.
- C sources under `native/oscore/`: the explicit lanes below and the
  `test/native/` sanitizer images.
- Package contents or `mix.exs` `package`: the full gate (archive check).

No sibling package depends on `wotex-coap`; it uses only the public APIs of
`wotex` and `wotex-runtime`. Consumers call its public API, so list callers
with `mix refs Wotex.CoAP.Module fun` and the tests to run with
`mix impact Wotex.CoAP.Module fun` before changing a public function.

Explicit-only lanes, never part of a bounded change; each needs a disposable
absolute workspace:

```console
mix wotex.native.build --package wotex-coap --workspace /absolute/disposable/dir
mix pkg wotex-coap wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-coap wotex.software.run --workspace /absolute/disposable/dir
```

The native build (also `mix pkg wotex-coap wotex.native.build --workspace ...`)
needs the native toolchain above (`$CC`, `$CMAKE` and `$OPENSSL_ROOT_DIR` select
other tools) and network access for the pinned libcoap archive. The software
build additionally needs a Java runtime (`java` or `$WOTEX_COAP_JAVA`) and
downloads the pinned Californium JAR; the run reuses the built workspace, uses
the same `OPENSSL_ROOT_DIR` and is terminal for that workspace.
`test/software/Dockerfile.linux` is the Linux environment for both software
commands; `test/native/Dockerfile*` build the ASan/UBSan images with Docker.
The `interop` and `software` tests run only inside these lanes. Apply the
shared `.claude/skills/spec-delivery/SKILL.md` for public behavior and
standards claims and `.claude/skills/release-readiness/SKILL.md` for
compatibility claims.
