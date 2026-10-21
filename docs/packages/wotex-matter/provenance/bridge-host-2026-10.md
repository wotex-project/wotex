# Production bridge executable evidence

Recorded: 2026-10-21. Package: `packages/wotex-matter`.
Source commit: `f79cc155bc33dce018d358d2f31ae20e96954996`.
Owners: [WMA.09](../specs/WMA.09-exposed-bridge-server.md) version 0.36.0-target,
[delivery plan](../plans/exposed-bridge-delivery.md) version 1.35.0 and
[software profile](../plans/exposed-bridge-profile.md) version 1.32.0.
The catalogue remains partial.

## Process assembly and exercised behavior

The production GN target builds
[`bridge_host.cpp`](../../../../packages/wotex-matter/native/src/bridge_host.cpp)
without fixture hooks. It composes the configured SDK process driver, guarded
consumer receiver and finite command renderer. Renderer attachment precedes
consumer attachment; consumer work joins outside SDK locking, then both
attachments finish under that lock before endpoint/resource retirement.
Arguments require exactly one explicit private configuration path. Checked
monotonic time, the original five-second startup budget, one-second cleanup
deadline, lock-free signal cancellation and fixed diagnostics retain the
existing coordinator's ownership rules. No configuration, credentials or
consumer policy are selected implicitly.

The guarded bootstrap fixture writes explicit pinned development material into
a private disposable directory, shuts down its own SDK memory and invokes the
separately supplied production executable through `fork`/`execv`. The child
resets inherited signal dispositions before exec. Independent stdout/stderr
pipes, literal protocol expectations, bounded waits and actual reaping exercise
the executable rather than substituting a fixture driver.

Each mode passes in ordinary and ASan/UBSan builds: `invocation`, `missing-open`,
`bad-open`, `partial-open`, `oversize-open`, `pre-ready`, `startup-timeout`,
`term-before-open`, `interrupt-before-open`, `missing-config`, `missing-dac`,
`permissions`, `symlink`, `interface`, `normal`, `reopen`, `store-exists`,
`store-locked`, `term`, `interrupt`, `output-lost`, `input-eof`, `partial-input`,
`malformed`, `generation` and `replay`.

These are 52 successful case-family executions. Argument cases cover eleven
invalid invocations, the exact 4096-byte bound and a lost diagnostic pipe.
First-open cases distinguish input refusal from private-load startup failure
and exercise the actual five-second expiry. Active cases require exact pinned
ready, clock-sample, observation and closed representations. Approved light and
temperature observations, nullable state, semantic refusal and 64 further
sequential observations traverse the real SDK observation owner. Reopen retains
endpoint identities; a concurrent process cannot acquire the active store and a
closed store releases its lock. SIGINT/SIGTERM before open and after ready,
input/output loss, malformed/partial input, foreign generation and replay produce
their required exits without a successful closed receipt. Stderr comparisons
require fixed diagnostics and exclude private input canaries or sanitizer output.

## Exact inputs and artifacts

The [source manifest](../../../../packages/wotex-matter/test/support/software/sources.json)
and [SDK process-driver record](bridge-sdk-process-2026-10.md) retain SDK revision
`250a9e6c50ee2068107f3c4808b680f5f2925415`, SDK archive SHA-256
`83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628`
and generated model SHA-256
`dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671`.
No model input or digest changes here.

Separate network-disabled Linux AMD64 containers mount current first-party
sources read-only over prepared pinned dependencies. The cached SDK-tools image
has immutable ID
`sha256:c7a0bf7283aa81f21d4fd653805548f625ccb361bfe95af6db9d146449075baa`.
Debian GCC 12.2.0 and Ninja 1.11.1 compile both targets in both graphs; subsequent builds report no
work pending. Sanitizer runs enable leak detection and halt on ASan/UBSan error.
No sanitizer fault is reported. This is focused qualification using cached
dependencies, not a fresh complete native/software build.

Both qualification snapshots match every member of the committed package's
`SoftwareManifest.identity/1`: 311 input members, canonical SHA-256
`c222a0aa2d6c2b759137a404c9580695cc29ad901db7f12a83e52d24aab2c1c0`.

| Artifact | Ordinary SHA-256 | ASan/UBSan SHA-256 |
| --- | --- | --- |
| Production bridge executable | `8b6e04d1c6e88919689fb00e78398cbfb43e1089b7dfeccae0de4442231fd571` | `7fed6f9fdb31e6c6846e97a6d8fefbf5f3d7bed514b4fb3c19a7be602a8d8769` |
| Guarded bootstrap/executable fixture | `d1d123c475b576fdf1e4a87f895ca32bc74740bc2b728fcb5f7f879e58f2bfa9` | `3b0a0536b507f8d2d75a378246519edd027abfd3c011a7a5362238ae95546802` |

The exact package archive SHA-256 is
`5809657d91daea82af85fbed68028e2b83c97afcc2b8a7a8b685c41715e2ac5b`.
The checker builds with `WOTEX_PATH_DEPS` unset, verifies exact contents and
normal Hex dependency identity, and compiles extracted source out of tree.
All three new native files are included; instructions, documentation, local
state and binaries are excluded. Disposable archive trees are removed. This
establishes archive contents/compilation, not independent native bridge adoption.

## Commands and limits

Commands run from the repository root. Native paths below normalize the explicit
disposable workspace; `${build}` selects ordinary or sanitizer graphs and
`${mode}` selects the 26 modes above. The Mix runner uses the owning
`SoftwareBridgeBuild.host_command/1` and `verify_host!/1`, requiring the exact
production-executable marker and actual zero fixture exit after child assertions.

```text
ninja --quiet -C /work/${build} -j4 obj/examples/wotex-matter-host/bin/wotex-matter-bridge-host obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test host-${mode} /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-bridge-host
mix native.lint --package wotex-matter --base 150dc44b --fix
mix pkg wotex-matter test test/wotex/matter/software_build_test.exs
mix check.fast --package wotex-matter
mix pkg wotex-matter run bin/check_archive.exs
mix affected --base 150dc44b --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

The focused runner suite passes 29 tests. The fast gate passes 385
tests/properties/doctests with 37 explicit-lane exclusions, formatting and Credo.
Only Matter is affected against `150dc44b`. Six catalogue tests, current generated
metadata, Markdown links and ExDoc generation pass. Both owned containers contain
only their sleep process after qualification and are then removed. Prepared
dependency/build caches remain available.

Full `mix check`, Dialyzer, SDK clang-tidy, fresh complete native/software builds,
interop/hardware lanes and benchmarks remain unrun under the focused workflow.
The new entry's clock-failure and signal-installation-failure branches are source
reviewed without injected production hooks. Live BEAM/SDK execution, authenticated
transport/process/probe admission, actual clock-rate qualification and independent
controller/reporting peers remain open. These pipe tests establish no consumer
authority, physical effect, containment, certification or complete WMA.09 result.
