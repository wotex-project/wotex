# CoreBluetooth archive consumer evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source commit: `69d14a973700c364898cc5cc725e39eae83cfd94`.
Owners: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md) version 0.11.0,
the [CoreBluetooth archive profile](../specs/WBL.08-corebluetooth-host-v1.md#independent-corebluetooth-archive-consumers)
version 0.9.0 and [completion contract](../plans/wotex-ble-completion.md)
version 1.11.0. This record closes the independent CoreBluetooth archive
milestone; installed Mac/controller qualification remains open.

## Executed boundary

The opt-in runner builds one exact core/Runtime/BLE archive cohort with sibling
source selection unset. Client and Runtime consumers have separate extracted
dependencies, build trees and locks. Inherited Mix build/dependency and Erlang
library paths are cleared. Locked runtime dependencies come from the provisioned
offline Hex cache; no sibling source or precompiled checkout BEAM supplies the
consumer libraries.

Each family runs one passive-loading case, one actual archived native build and
seven behavioral cases. Module origins must be inside that consumer's build.
Passive loading starts none of the three libraries and creates no Port or peer.
The public builder compiles the archived macOS host and guardian, checks the
exact passive ready receipt, embedded usage metadata and IOKit linkage, then
verifies read-only reuse. Both builds report `system_power_observation=iokit`.
The macOS 14 deployment target is a compiler setting, not runtime qualification
on macOS 14.

The independently written C++ process peer imports only the archive's JSON
syntax parser. It owns literal frames, route identities, faults and byte traces;
no production protocol, binding, codec or lifecycle helper supplies its behavior.
Behavioral cases execute public APIs through the archived guardian. They use the
independent peer, rather than the actual framework-linked host, for GATT traffic.
Public Runtime transport callbacks provide the uncertainty oracle before Runtime
projects the error into its documented permanent, non-retryable form. Runtime
does not retain the native effect field in its public cause.

| Case | Client consumer | Runtime consumer |
| --- | --- | --- |
| 1 | Typed reads, duplicate routes, exact empty/two/512-byte writes and both modes | Typed point Results, exact writes and accepted command status |
| 2 | Invalid modes, size, generation, ambiguous route and artifact digest send no operation | Real Property/Event streams preserve repeated values and native metadata |
| 3 | Null command reply, missing submission, wrong ID and post-submission loss preserve uncertainty without retry | Target, security, selector and expired Context refuse before native startup |
| 4 | Public stream credit, exact binding, repeated values and ordered retirement | Native command faults preserve transport uncertainty and permanent Runtime retry refusal |
| 5 | Codec refusal returns credit only after the native retirement fence | Actual public decoder refuses CoreBluetooth metadata under a foreign backend |
| 6 | Queued expiry sends nothing; submitted timeout retires the actual peer | Independent Runtime sessions and receiver/owner loss join native cleanup |
| 7 | Independent sessions, receiver/owner loss, missing retirement and malformed startup/stream input | Incompatible startup, binding and bytes cannot become Runtime values |

The final run passes all eighteen baseline cases with zero failures, skips,
exclusions or harness errors. Each mutation runs all seven behavioral cases in
a fresh VM. Recompilation changes one guarded semantic site in that VM; it does
not modify the extracted archive source or another consumer's loaded modules.

| Family | Mutation | Failed cases | Assertion failures | Harness errors |
| --- | --- | ---: | ---: | ---: |
| Client | Command becomes acknowledged write | 3 | 3 | 0 |
| Client | Null reply fabricates queue acceptance | 1 | 1 | 0 |
| Client | Report credit returns before receiver admission | 2 | 2 | 0 |
| Runtime | Accepted status becomes ordinary success | 1 | 1 | 0 |
| Runtime | Target matching is bypassed | 1 | 1 | 0 |
| Runtime | CoreBluetooth metadata is admitted under BlueZ | 1 | 1 | 0 |

All six mutations are caught through assertions: forty-two executed mutation
cases, nine failed cases/assertions and zero harness errors, skips or exclusions.
The runner rejects absent/duplicate markers, wrong totals, compiler warnings,
runtime errors and surviving mutations. The final lane exits zero only after
removing its complete workspace; a separate existence check confirms removal.
Per-case cleanup checks actual peer PIDs before removing their trace directories.

## Commands and results

Commands ran from the repository root on macOS 27.0.1 ARM64, Elixir 1.20.2 /
OTP 29.0.4, Apple SDK 27.0 and LLVM 23.1.3 clang tools.

```text
mix check.fast --package wotex-ble
MIX_ENV=test mix pkg wotex-ble run --no-start bin/check_archive.exs
MIX_ENV=test mix pkg wotex-ble run --no-start bin/check_archive.exs --corebluetooth-consumers
mix test test/wotex/workspace/catalogue_test.exs
mix affected --base 714f727a --detail
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
```

The fast gate passes 416 cases: nine doctests, seventeen properties and 390 tests,
with 58 explicit-lane exclusions. Strict Credo, formatting and the native changed-line
format check pass. Direct clang-tidy analysis of the new peer reports no findings
in its source; the temporary include tree selects the repository copy of the
same archived JSON header and is removed afterward. Vendor/header diagnostics
are suppressed by the checker. This static check is separate from the actual
extracted-header peer compilation in each consumer.

Six root catalogue tests, catalogue generation, Markdown links and ExDoc pass.
The affected set against `714f727a` is BLE only. The ordinary archive check
verifies exact members/source bytes and out-of-tree Elixir compilation. Its five
retained archive files are removed after exact file-list and SHA-256 verification.
Both ordinary and opt-in archive checks complete without the former optional
consumer-module compile warning.

Full gates, Dialyzer, coverage, dependency audits, the older BlueZ write-mode
consumer lane, Linux native/software lanes, sanitizers and hardware lanes were
not run for this archive-tooling milestone. The unchanged native production
paths retain their separately scoped [power lifecycle evidence](corebluetooth-power-2026-10.md).
No real manager, permission request, power observer, peripheral or radio operation
is exercised by this lane. It establishes no pairing, installed sleep/wake,
physical-effect or controller/RF result. WBL.08 remains partial.

## Exact artifacts

Both independent consumers resolve the same lock and compile the same peer,
host and guardian digests, each in its own tree.

| Artifact | SHA-256 |
| --- | --- |
| Core archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| Runtime archive | `0b5bc1da977f0dd41c0df81038f4531a04255a65949c030b741d4d1b79861fd4` |
| BLE archive | `6874d2507b504f1c0258e3121a8d87e986c2904e3175b26a65222269bd968ae4` |
| BLE package lock | `50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4` |
| Each consumer lock | `bf17a9752b6d1d9c5fa204e21c0c6928256cd18afcd6f40d1aefebae49d1a42a` |
| Each independent peer binary | `aa632490150f874897977412ab99a60505de004929f1b7e78f5751c1c3b35bb9` |
| Each archived native host | `4ba86227b8d100c494cb99c459ed0383c32ab91e3084939c8221dbea14ba64ee` |
| Each archived guardian | `5f4579dea3b1ee8272fe38b377dbb46f32da5b392f055a3061d0ab7513bc672f` |
| Native build source revision | `3e2a3a91971ffe66407c6191de1fc851e1bf55acc96bec53695179f3c286f105` |

## Exact runner inputs

Paths are relative to `packages/wotex-ble` at the source commit above.

| Path | SHA-256 |
| --- | --- |
| `bin/check_archive.exs` | `7a8c4d31908721d73833177a844edb36b1149ad016be4424cf6a3e64949e4599` |
| `bin/corebluetooth_consumers.exs` | `67e7eadf271f8d9c54f25c369c5bb1672225c8241740ed6c64bc2de3fd4222a3` |
| `test/support/archive/corebluetooth_identity.exs` | `2d837a117de9bbcbefd4124bda1abf7c6354c433f4a3eb5f3b12633639dd60d2` |
| `test/support/archive/corebluetooth_build.exs` | `0a2d171c706a1114709bb75be5a430df5ae04764767477dff90c06e7a9710955` |
| `test/support/archive/corebluetooth_runner.exs` | `5aed0a9518710acb158a676a0bea4d1fb02e4ec884f675876a4bf88293d6c53d` |
| `test/support/archive/corebluetooth_support.exs` | `68daaf01d8c48dfb81b3fa75d04612fc4ad7542414decf8df1f26cfc06c2dba4` |
| `test/support/archive/corebluetooth_client_consumer.exs` | `a8ec55335b59a0409f378e5f75fc0ec5301df3190f206c77ae1d63d0489e3f05` |
| `test/support/archive/corebluetooth_runtime_consumer.exs` | `deee21e2aa15bfc26e0b3b970226e2eaa1c4294db3b56cab8a86c119ebf7c645` |
| `test/support/archive/corebluetooth_peer.cpp` | `4ac2afb9d779175dc225fdebafd69100416f6cadef06eeafbcae388b5303ff67` |
| `test/wotex/ble/corebluetooth_archive_runner_test.exs` | `2bc201104facd7c2a2aa83b5ab2a993529bddf4dbd1851bc7d5b4986ff12a2b0` |
