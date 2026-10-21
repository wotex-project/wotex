# Trusted codec task custody evidence

Recorded: 2026-10-21. Package: `packages/wotex-runtime`.
Source commit: `e016938489a2fef98d9e9c9520aa466f85df8b93`.
Owner: [WRT.06](../specs/WRT.06-bounded-codec.md) version 1.4.1 and the
[completion contract](../plans/wotex-runtime-completion.md). WRT.06 remains partial.

## Behavior and falsifiers

The previous executor called Task.Supervisor synchronously in the decoding
caller, then began a fresh full wait. A suspended supervisor could therefore
hold startup indefinitely, and decoder entry could occur after expiry or
revocation. Cleanup also used a fixed 1,000 ms wait rather than an admitted lower
ceiling. Output admission could exceed the VM budget while a supplied clock
remained unchanged.

The explicit trusted BEAM executor now uses a local consumer-owned supervisor,
a startup actor and an independently responsive custodian. One VM timer begins
before supervised startup and remains charged through output admission. The
worker attaches before entry, checks current admission and the original
clock/budget, and receives only the decoder's existing bytes/metadata/configuration
arguments. Confirmed cleanup requires both startup actor and known worker to
terminate. A pending supervisor start that cannot settle within the admitted
cleanup budget returns cleanup_unconfirmed; its late task cannot enter decoding.
Owner loss follows the same custody. Cleanup uses min(1,000, admitted shutdown_ms),
including zero, without renewal. No retry, fallback or replacement is added.

A monitored timer relay uses a deactivatable alias, so a notification still in
flight cannot enter the caller after return. Relay loss cancels known work
and returns enforcement_unavailable after confirmed cleanup. Timer cancellation
alone does not prove notification delivery, as specified by
[ERTS timer cancellation](https://www.erlang.org/doc/apps/erts/erlang.html#cancel_timer/1).
This design applies that rule to internal notification retirement; it does not
qualify a consumer's clock or provide VM/native isolation.

The final owning test file has thirteen cases. Its seven additional cases cover
stalled startup with unconfirmed cleanup, expiry/revocation before decoder entry,
owner loss during startup, resumed-start cleanup, admitted lower/zero cleanup,
late output admission with a stationary supplied clock, and timer-relay loss.
Existing cases retain determinism, separate instances, overload, hung workers,
late output/refusals, current policy, custodian loss and diagnostic redaction.
The malformed-configuration corpus also includes a literal remote supervisor pid,
without starting or connecting a node.

An isolated VM loads the previous Beam module from commit `4cd412b6f02a9a9a33825f9bbf94430b6c687bff`, while using
the current test file. Previous Beam SHA-256:
`d0b70b47b9c1bbcb2903f68a1c2ef0a66171bb9a1564d1ddca716887788a98b8`.
ExUnit uses seed 19/max_cases 1 and excludes only the new relay-loss test, which
refers to an actor absent from that implementation. The other twelve cases
execute: seven pass and five fail through assertions, with zero harness errors
or skips. The failures are expired entry, resumed-start entry, stalled
startup's bounded result, lower cleanup and late output admission. No checkout
source or installed BEAM is replaced; the old module exists only in that VM.
The current full fast gate runs the relay case and all other tests with no exclusions.

## Validation and artifacts

Executed from the repository root:

```text
mix pkg wotex-runtime deps.get
mix pkg wotex-modbus deps.get
mix pkg wotex-runtime test test/wotex/runtime/codec_beam_test.exs test/wotex/runtime/codec_test.exs test/wotex/runtime/codec_json_test.exs
mix check.fast --package wotex-runtime
mix pkg wotex-modbus test test/wotex/modbus/register_codec_test.exs
MIX_ENV=test mix pkg wotex-runtime run bin/check_package.exs
mix affected --base 4cd412b6 --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-runtime
```

Both previously unprepared package dependency directories are provisioned from
their existing locks; no lock or dependency version changes. The final fast gate
passes compilation, formatting, strict Credo and 150 checks (1 doctest,
149 tests). The direct Modbus packed-decimal consumer passes five tests, using
current Runtime code through the public Beam executor. Six catalogue tests,
generated metadata, Markdown links and ExDoc pass. The earlier focused
codec/JSON run passed 29 tests; the final fast gate renews the complete corpus,
including the subsequently added relay fault case.

The existing package checker builds exact core/Runtime archives with
WOTEX_PATH_DEPS unset in the build subprocesses, verifies contents/boundaries,
and runs two isolated public consumer cases with locked extracted dependencies.
It excludes test, contributor and documentation trees. These consumer cases
exercise passive package loading, dispatch and wire framing; they do not
exercise the new task custodian or establish independent codec adoption.

| Artifact | SHA-256 |
| --- | --- |
| Runtime archive | `1d5d8c6f14f876892890385bc49b9b88a7c876fa55100fb41a5c9f5126d0eb90` |
| Core archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| Isolated consumer lock | `6ddb05e87f2872a12a244a022d666372d792510c8760188a3ac235ce53c258dd` |

The selected local cohort is Elixir 1.20.2/Erlang OTP 29 (ERTS 17.0.4), macOS
ARM64. No minimum-toolchain, distributed-node, native enforcement, hardware or
physical-effect qualification is inferred.

The following committed inputs were compared byte for byte before recording:

| Package-relative input | SHA-256 |
| --- | --- |
| `lib/wotex/runtime/codec/beam.ex` | `d358e907cf3e99a1c12d00ec69513a858f1f63b1de2a9b46875d25de9f2fa683` |
| `lib/wotex/runtime/codec/beam/execution.ex` | `00183b8932b5f1140e9e67cf47f1fa8719698ba983890c21f56dc5e3886eef6c` |
| `test/wotex/runtime/codec_beam_test.exs` | `7ce94ce9c057400f9ade92bb4e7ae921e3178beb73e1046f374e24cf594da51b` |
| `test/support/codec_decoder.ex` | `656da8134eb7be394058d3c70301ca97e3c898d8c55d39b24916a70cc1f42548` |
| `README.md` | `6d13d60916c721e2a3948eef31577aff5f1fe1588e684c82dc3aaa09a0e7d1bc` |
| `mix.lock` | `50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4` |

Full mix check, Dialyzer, all dependent package gates, native/software/hardware
lanes and benchmarks are unrun. The affected graph includes Runtime dependents;
validation selects the direct Beam consumer and owning suites rather than every
binding. Native process custody remains binding-owned. Wider admission/lifecycle
integration, native resource enforcement and independent consumer/usefulness
qualification remain open.
