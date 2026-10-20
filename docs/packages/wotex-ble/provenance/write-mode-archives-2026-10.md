# Independent write-mode archive consumers

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source parent: `adc76a891cd7bf1f2858c10bc767c31eda9c69e3`. The complete dirty-input
identities below bind the new runner/fixtures and corrected request typespec
before their owning commit. Runtime behavior is unchanged from the parent.
Owner: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md) version 0.2.1,
principally the BlueZ archive portion of WBL08-T5.

## Executed boundary

Two separate projects compile the same exact core/Runtime/BLE archives through
only extracted path dependencies, each with `env: :prod, override: true`.
Sibling selection, Mix build/dependency/app paths and Erlang library paths are
cleared. Each project's public modules load exclusively from its fresh build.
A separate fresh VM proves library callbacks absent and libraries unstarted;
constructing a public Peer starts no application. Behavioral runs explicitly
start their application dependencies only after that passive check.

The wire family implements its own bounded JSON-line process peer in Elixir;
it imports no WoTEx helper, protocol decoder or existing native fixture. The
archive's C custody source builds its guardian. A private wrapper selects the
exact provisioned Elixir/Erlang launchers and a minimal runtime PATH under the
otherwise cleared native environment. It records literal operations and bytes,
then supplies independent normal, legacy and malformed replies.

The Runtime family supplies separate Client and NoSec credential ports. Its
expected modes, byte values, payloads, request IDs, status and refusal outcomes
are literal consumer assertions; it calls only documented public package APIs.
No source checkout supplies consumer modules or dependency BEAMs.

## Commands and results

Commands ran from the repository root with Elixir 1.20.2 / OTP 29.0.4 on
macOS 27.0.1 ARM64. The archive guardian used Apple clang 21.0.0
(`clang-2100.3.34.2`) with the exact C11 arguments in the runner:

```text
mix pkg wotex-ble test test/wotex/ble/archive_consumer_runner_test.exs
MIX_ENV=test mix pkg wotex-ble run --no-start bin/check_archive.exs --write-mode-consumers
mix check.fast --package wotex-ble
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
mix workspace
```

Both families pass their one-case passive identity run and all five behavioral
cases: twelve passing baseline cases overall. Each mutation runs all five
behavioral cases in a fresh VM and changes only the selected in-memory module.

| Family / mutation | Executed cases | Assertion failures | Harness errors | Skipped/excluded |
| --- | --- | --- | --- | --- |
| wire / command_substitution | 5 | 4 | 0 | 0 / 0 |
| wire / fabricated_acceptance | 5 | 1 | 0 | 0 / 0 |
| Runtime / lost_accepted_status | 5 | 2 | 0 | 0 / 0 |
| Runtime / ignored_read_selector | 5 | 1 | 0 | 0 / 0 |

The runner refuses missing, duplicate or malformed result markers, mismatched
process statuses, missing cases, surviving mutations and non-assertion failures.
Its focused refusal matrix passes. The final fast gate passes compilation,
formatting, strict Credo, native formatting and 309 cases (nine doctests,
seventeen properties and 283 tests); 58 explicit-lane cases are excluded.
The root workspace checks and documentation links pass separately.

The wire cases preserve empty, two-byte and 512-byte payloads, default/explicit
acknowledged writes and explicit queue evidence. Invalid options, value and
address acquire no wire request. Legacy replies refuse without fallback;
null, wrong evidence, extra fields, wrong IDs and missing submission events
cannot settle a command. A queued command expires unsent while the submitted
original remains uncertain. Separate peers retain independent state; owner loss
retires the actual peer, with process disappearance checked before cleanup.

The Runtime cases preserve native queue payload and `:accepted`, acknowledged
`:written`/`:ok`, exact caller identity and remaining budgets. Wrong selector
applicability refuses before acquisition. Null/acknowledged/widened command
evidence refuses without retry; separate consumers and expired requests do not
leak selections or acquire another client.

## Exact artifacts

| Artifact | SHA-256 |
| --- | --- |
| core archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| Runtime archive | `0b5bc1da977f0dd41c0df81038f4531a04255a65949c030b741d4d1b79861fd4` |
| BLE archive | `96c8c2c670d2363bdf288b02db2df278d84e19fa31168cf343d10176128ff2e9` |
| each consumer lock | `6ddb05e87f2872a12a244a022d666372d792510c8760188a3ac235ce53c258dd` |
| compiled archive guardian | `9d1737264b997e80765f05e090eb439ae8702c7453972090391c16d60e4fed30` |
| Elixir launcher | `f33a0a2e3b5871c137460b7e71cd2b15c1b997fbccb3ab70b55b1683d196e02c` |
| Erlang launcher | `c3e7e6d7a8c70f9b589b0ee2ff49cb27ee72e886768703dd5676e08113cc6fd0` |

## Source identities

Paths are relative to `packages/wotex-ble`.

| File | SHA-256 |
| --- | --- |
| `bin/check_archive.exs` | `34f6efd713eff82ccbee26c8030cba5156c2aac3a02e8a8ac5a67dd30cfe97bd` |
| `bin/write_mode_consumers.exs` | `bd3730fbd1f818590613bd4c69fd5b849c0a950b6950c8d77d4886e7b53ea77a` |
| `lib/wotex/ble/bluez/connection.ex` | `99cbfdec66ff4c1147d575661897da79af953fff0da49bb54bca03a7148f5908` |
| `test/support/archive/write_identity.exs` | `44d55bceeb3ee52db956f5b65d5f108777053c3d80b3f5af0f71f20e2bd20112` |
| `test/support/archive/write_runner.exs` | `8fffa524e4c0e1b4893e8f1ec95feb064dc794cd6ec9f69125fd3a7a8b1ec1a5` |
| `test/support/archive/write_peer.exs` | `5eb03530edd0578d0db2b96645419b7471a92b4106eb730f1c374411bc60bffc` |
| `test/support/archive/write_wire_consumer.exs` | `698c281ad07d8a76a2dd41af630544536c824d0094b68714d5487f154c76d121` |
| `test/support/archive/write_runtime_client.exs` | `89a563866101d55abc1ba412989d869914f30c413bccbe2f474a5341fc15eabc` |
| `test/support/archive/write_runtime_consumer.exs` | `0f2af8ace092b7af528bfc2a59cc208aa50122eb9fcd767642e6aded42203b1f` |
| `test/wotex/ble/archive_consumer_runner_test.exs` | `12e70987158b497a648e353d3fffa4da3fa52d1050699d47a05df24751775206` |
| `mix.lock` | `50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4` |

## Cleanup and remaining qualification

The parent reported `write-mode workspace cleanup: removed`; the complete owned
workspace was independently checked absent after successful execution. Consumer
callbacks checked actual peer retirement before removing their instance files.
No Docker resource was created; reusable compiler/dependency/build caches remain.
The ordinary archive contents and out-of-tree compilation check also passed.

The first attempt exposed a fixture launcher dependency on inherited PATH; an
explicit Erlang launcher fixed it. A later run refused an assertion marker joined
to ExUnit progress dots; leading newline framing fixed that harness output. Both
were rerun through the final complete lane and are not counted as passing evidence.

These are archive/software results, not actual BlueZ, installed controller,
CoreBluetooth, RF or physical-effect qualification. WBL.08 remains partial.
No Dialyzer/full coverage, native SDK, sanitizer, clang-tidy, virtual-controller
or physical lane ran for this tooling/type-only change. No release or dependency
selection changed.
