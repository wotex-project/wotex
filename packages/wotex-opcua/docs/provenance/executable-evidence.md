# Executable evidence

Evidence collected 2026-09-08 using Elixir 1.20.2 / OTP 29.0.4.
That historical baseline covered the stated toolchain only. The package
requires fresh source-specific matrix and archive checks before graduation. No consumer parity or
certification is inferred from unit coverage.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. The native build test is required by this
gate: it downloads the pinned archives, executes the static build and CTest, and
checks receipt reuse/tampering in an owned temporary workspace. The gate requires
CMake 3.20+, a C11 compiler, make, Perl, Python 3, archive utilities and curl 8.4.0+.
`mix test` excludes this lane; selecting `native_build` without its explicit
`WOTEX_NATIVE_BUILD_WORKSPACE` fails. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Pipe-independent X-F21 owner trace, 2026-09-17

A Linux arm64 run (Docker container from the local `hexpm/elixir` image
`sha256:290e52da1c5d5cbf62344d384387e8bdfa7d8a64784302bb7770e76ad13c88a5`,
Debian 12, Elixir 1.20.2 / OTP 29, GCC 12.2.0, CMake 3.25.1, curl 8.14.1 from
bookworm-backports) built the pinned SDK and passed 203 of 204 native CTest
cases. `native_contract_WOP-X-F21` emitted only 8 credited reports before
`receiver_overflow`, not 16. Instrumentation showed 8 reports and 8192 bytes
emitted with a queue peak of 64. In that container a new pipe has 8192 bytes
(`F_GETPIPE_SZ`), because the shared kernel's `pipe-user-pages-soft` limit
(16384 pages) is exceeded, so the trace pipe filled before the 16-message
credit ran out. The production owner still respects credit as an upper bound;
the trace harness wrongly depended on pipe capacity.

`owner_check.c` now replaces the X-F21 trace pipe with a nonblocking `AF_UNIX`
socket pair whose send and receive buffers request 262,144 bytes. With that
source copied into the container build, Linux arm64 CTest passes 204/204.
macOS RelWithDebInfo CTest passes 204/204 and macOS ASan/UBSan CTest passes
204 of 213 (the nine LeakSanitizer custody cases are unavailable on macOS).
A complete Linux cohort run of the committed tree is recorded separately.

`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 364 passed (10 doctests,
4 properties, 350 tests), 62 optional tests excluded and 95.3% coverage.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/owner_check.c` | `6f015c62ad795dbd7d757a33fb449578fc3ef6f4aa5df2f7846296fb44acad87` |
| macOS native CTest log | `dcf3c137246e6d6b5703f87964864fee7a850201d6bdfd3b3ed056def1e67f65` |

## Tampered and replayed secure responses, 2026-09-17

`test/interop/tampered_traffic_test.exs` places an Elixir TCP proxy between the
production native executable and the independent asyncua 2.0.1 peer. The proxy
forwards client bytes unchanged and forwards the server's complete OPC UA TCP
chunks. On request it either flips the last byte of the next server `MSG` chunk
(its signature area under Basic256Sha256 SignAndEncrypt) or sends the previous
`MSG` chunk again before the next one. Each Session first completes a Read
through the proxy. Afterwards:

- a Read whose response chunk is tampered fails with `connection_failed` or
  `invalid_response`, effect none, and no value. The host stops and its
  guardian and SDK OS processes exit within 1,000 ms;
- a Read preceded by a replayed earlier response chunk fails the same way and
  releases the native processes; a direct Session then reads the unchanged
  value;
- a Write whose response chunk is tampered fails with effect `unknown`, the host
  stops, and a direct Session restores the value.

The proxy reports each alteration and the tests require that report. A forged
service type or requestHandle inside an encrypted chunk cannot be built without
the channel keys and is not executed.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29: the file passes
3/3 against the RelWithDebInfo and macOS ASan/UBSan builds. The optional secure
suite with the lifecycle file passes 58/58 against both builds.
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 364 passed (10 doctests,
4 properties, 350 tests), 62 optional tests excluded and 95.3% coverage.

| Subject | SHA-256 |
| --- | --- |
| `test/interop/tampered_traffic_test.exs` | `8aaa89e75b19f29becc34bf69db072aa0fb3d08b04aeffbbe17b2f58caa15e5c` |

## Software stress lane and minimum runtime, 2026-09-17

`test/software/lifecycle_stress_test.exs` carries the `interop` and `software`
tags; the default test helper now excludes `software` as well. It needs the
independent asyncua 2.0.1 peer and one native build.

- Operations: one persistent Basic256Sha256 Session performs 2000 sequential
  operations (a Method call every tenth, otherwise Reads). Then 32 concurrent
  callers each make 16 Calls whose outputs must equal their own distinct inputs.
  Then 50 Reads with a 1 ms timeout each end in `deadline_exceeded` or `busy`.
  Pending work and controls drain, and a later Read succeeds. Growth from the
  first to the second 1000-operation batch, through the concurrent and
  deadline phases, must stay under 1 MiB of host process memory and 16 MiB of
  guardian plus SDK process RSS. Close releases both OS processes within
  1,000 ms.
- 100 open/Read/close cycles: each releases its host and native OS processes
  within 1,000 ms; the BEAM port and process counts return to their start
  values; and the peer reports zero subscriptions.
- 100 receiver-death cycles on one Session: each subscription is removed after
  its receiver is killed, controls drain, the peer reports zero subscriptions
  and MonitoredItems, and the Session still reads.
- 100 generations with an unsolicited native reply (deterministic C probe):
  each ends once with `invalid_native_frame`, and both OS processes are reaped.

Results on macOS arm64 with Elixir 1.20.2 / OTP 29 (`mix test --include interop
--include software --seed 0 test/software/lifecycle_stress_test.exs` with the
peer environment described above): 4/4 against the RelWithDebInfo build (host
memory 2992/2992->2992 bytes; native RSS 9584/9856->9904 KiB, as start/after
warm-up->end) and 4/4 against the macOS ASan/UBSan build (native RSS
49328/98784->108544 KiB; the sanitizer allocator grows during the first batch). A single-batch RSS bound that included
warm-up failed under ASan/UBSan with 54 MiB growth, which is why the bound is
measured from the second batch. Peer loss is exercised by
`subscription_lifecycle_test.exs`, not repeated in this lane.

The default suite also runs on Elixir 1.18.4 compiled with OTP 27, with
Erlang/OTP 27.3.4.15, a separate build root and `mix compile --warnings-as-errors`:
10 doctests, 4 properties and 409 tests (the 1.18 count includes excluded tests),
0 failures and 60 excluded. That run repeats no native build and no peer lane.
Linux cohorts, the software Mix tasks and the archive consumer (X-F48) are not
executed.

`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 364 passed (10 doctests,
4 properties, 350 tests), 59 optional tests excluded and 95.3% coverage.

| Subject | SHA-256 |
| --- | --- |
| `test/software/lifecycle_stress_test.exs` | `63f007ac4624dbad565d4e3ffb0bfed3a52a5fc6f4131001f0d86cc5fa57605b` |
| `test/test_helper.exs` | `9f486e6a6a69aa14066d212f54a10312b2d503853986ede605f83859eb5c86fa` |

## Bounded native output owed after request timeouts, 2026-09-17

A software stress run against the macOS ASan/UBSan build ended a Session with
`receiver_overflow` after 50 sequential Reads with a 1 ms timeout. Each timed-out
request owed one response and its cancellation one acknowledgement, and the
slower native process read the whole burst at once and produced more than the
16 credited plus 64 queued envelopes. `Native.Host` now counts every pending
request and control as one owed native output line. A request is admitted only
while fewer than 64 are owed, and a timeout or caller death sends `cancel` only
while fewer than 80 are owed; otherwise the native deadline ends that request.

`persistent_bridge_test.exs` stops the process-fixture owner with `SIGSTOP`,
issues 100 Reads with 5 ms timeouts, and resumes it. Every result is
`deadline_exceeded` or `busy`, at least one is `busy`, at most 80 lines are
owed, pending work and controls drain, no terminal error reaches the owner, and
a later Read and close succeed. Against the previous host the same stimulus
leaves 198 owed lines.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29:
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 364 passed (10 doctests,
4 properties, 350 tests), 55 optional tests excluded and 95.3% coverage. The
optional secure suite with the lifecycle file passes 55/55 against the
RelWithDebInfo and macOS ASan/UBSan builds. Report bursts from active
subscriptions are not counted as owed lines.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/native/host.ex` | `aeb16a19b71209247458b0cc825f8bbcac233b298472a188c2a8664c6188a586` |
| `test/wotex/opcua/persistent_bridge_test.exs` | `e154409e4d01c94646ec56cca469b412d7402513dde10bb823d06f2a8a6ea01f` |

## Runtime binding profiles and the integration corpus, 2026-09-17

`Wotex.OPCUA.profile/0` returns the static one-shot `:opcua` profile (`opc.tcp`,
readproperty and writeproperty, no media types). `profile/1` returns it for
`:oneshot`, returns `:opcua_session` (adding observeproperty and
unobserveproperty) for `:session`, and returns `unsupported_profile` otherwise.
`Mapping` rejects a Form that supplies `contentType` with
`unsupported_content_type`. `Transport` projects a persistent native Read
through `Value.native_result/1` and a persistent Write as a nil payload with
status metadata, and removes the observation-only options before opening a
request Session. `invalid_native_configuration` is now classified `:permanent`.

`runtime_integration_test.exs` binds WOP-I-F01. It builds the input Thing
Description, `Wotex.OPCUA.profile()` and a ConsumedThing whose Transport is the
production Transport behind a recording wrapper. A scripted client returns only
the input peer reply. The runner projects the profile id, the resolved href
Runtime selected, the command the client received, the Result fields, the
unchanged Form extension, the number of client requests and the balance of
connect and disconnect calls; the projection equals the expectation. Further
tests check the static profile contents and rejected modes, a `contentType`
Form failing with no client call, and session-profile Read, Write and Bad-status
projection with one connect, request and disconnect each. The corpus status is
now `executed`, with bindings for F01 through F07.

In `native_runtime_stream_test.exs`, against the independent asyncua 2.0.1 peer,
a session-profile ConsumedThing reads the Double Variable and writes 44.5
(nil payload, status 0). A one-shot-profile ConsumedThing reads 44.5 and writes
45.5 (`written`). Only the session profile builds an observation child, which
delivers 45.5, and after stop the peer subscription counts are zero.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29:
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 363 passed (10 doctests,
4 properties, 349 tests), 55 optional tests excluded and 95.3% coverage. The
optional secure suite with the lifecycle file passes 55/55 against the
RelWithDebInfo and macOS ASan/UBSan builds (native executable digests unchanged).
The archive consumer, the minimum Elixir/OTP matrix and I06 package-archive
runs are not executed.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua.ex` | `5752af2ffa5930fdc0b5af8d92bee8f113770bda548f5c880fb926611e4de9fd` |
| `lib/wotex/opcua/transport.ex` | `ff8bd47bb8a5fdec57ac97863ebee927a81c9d2753428ee2d1c4548708c82f5a` |
| `lib/wotex/opcua/mapping.ex` | `e0e47cf05b4f0c55cac3729ab2250c6253ba8bcaa1b4fb7a8b64213d56063e2a` |
| `lib/wotex/opcua/error.ex` | `0c2496c27b9ae5a82381b59b3bb70d80405851b04c724d5e653328808bcc7100` |
| `test/support/scripted_client.ex` | `356f828e37bd97fadcfccc11cf368f6c1fb054ed49ca705ed95fa2bc6448194d` |
| `test/support/recording_transport.ex` | `cb819b2a89da0262925be57e89a666ae0ac6b583ef1702d7baf0b7e7f3dbde1d` |
| `test/wotex/opcua/runtime_integration_test.exs` | `de12fe961021f667538196c540537a21fe372688fcbb1940f06b82834128cda0` |
| `test/interop/native_runtime_stream_test.exs` | `159e6f9f63e139baeac9b08970d821015ebf2bd7d73af2b01f584e4ad5a7a89c` |
| `docs/specs/fixtures/wotex-integration-v1.json` | `ea833add56b940314aaac56f5ea6abeaf0d7308996d3ba160a9f2e36dea51634` |

## Runtime error classes and retry decisions, 2026-09-17

`Wotex.OPCUA.Error` gains the additive `class` field. `Error.classify/1` maps an
unknown effect to `:permanent`. Otherwise deadlines map to `:timeout`,
connection and native process loss to `:unavailable`, `busy` to
`:rate_limited`, mismatched or malformed responses to `:protocol`, and invalid
input, route, security or unsupported operations to `:permanent`; other codes
stay `nil`. It sets `retryable` only for the first three classes with no
effect. `Transport` classifies every error it returns to Runtime.

`runtime_integration_test.exs` binds WOP-I-F02 through F07. Each case builds a
real Thing Description, a test binding profile admitting only the input
operation and a ConsumedThing. Its test Transport returns the input native
code and effect through `Error.classify/1`. The runner projects Runtime's class,
cause code, whether the cause retained an effect and `Runtime.Retry.decision/3`
with the input options, and compares that with the expectation. Extra cases
cover unclassified failures, a default non-idempotent Write timeout, an
unknown-effect mutation marked idempotent, an admission budget with and without
remaining attempts, protocol, unavailable and authentication failures. The
production Transport returns classified target, transport, unknown-effect Write,
Event, handle and frame errors.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29:
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 360 passed (10 doctests,
4 properties, 346 tests), 54 optional tests excluded and 95.3% coverage. The
optional secure suite with the lifecycle file still passes 54/54 against the
RelWithDebInfo build.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/error.ex` | `61d13316977e21cf7847ecd94219465d3ccb71b4c04ad8fc9cb26263cdff4d68` |
| `lib/wotex/opcua/transport.ex` | `47f4754a1be0311d2cb8dad260e6ac6dc7aad3163d02d7a28438f40ee2646c0f` |
| `test/support/failure_transport.ex` | `74dc9ef6ceeb90cb26b52cf60881b795d3e0fa4ce899e7bc1fa47fde26aa940f` |
| `test/wotex/opcua/runtime_integration_test.exs` | `05a893b7a4f925fb69ece471a4626d5c505934b15304dd71660929f83ec9569e` |
| `docs/specs/fixtures/wotex-integration-v1.json` | `f592760b4ddbd15c40f110b247e5184f9f3591a717a5ba45c69094b2187a64e4` |

## Bound secure policy and user-token workflows, 2026-09-17

`security_fault_test.exs` now binds WOP-X-F30 through F38 against the
independent asyncua 2.0.1 peer. For each policy and user-token cell, the runner
opens a Session and subscribes to the Double Variable. It then records success
for read, write, readback, Method call, typed Browse of the Objects folder
(Status Good, the Method among the references and no continuation), receipt of
one subscription report, subscription cancellation and close. After
cancellation it reads the peer's active subscription count through the
Resources Method. It reads the host's live continuation count before close;
because the peer returns every reference in one page with no continuation
point, no peer continuation can exist for the Session. After close it counts
the host process and its guardian and SDK OS processes that are still alive.
The observed map
`operations_succeeded`, `active_peer_subscriptions`,
`active_peer_continuations` and `active_local_resources` must equal the
corpus expectation (8, 0, 0 and 0) for all nine cells, and the recorded
operation names must equal the corpus list.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29: the optional
secure suite with the lifecycle file passes 54/54 against the RelWithDebInfo
and macOS ASan/UBSan builds, whose executable digests are unchanged, and
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 352 passed (10 doctests,
4 properties, 338 tests), 54 optional tests excluded and 95.3% coverage.
Tampered or replayed traffic (V09), user-token encryption algorithm assertions
and Linux cohorts are not executed.

| Subject | SHA-256 |
| --- | --- |
| `test/interop/security_fault_test.exs` | `b3c870aa1483cc3953b956f0e57facceed6bc25b54f991924c13c6b794598a09` |
| `docs/specs/fixtures/native-contract-v1.json` | `e81f63e897fba024a64a2022f80ffdab6700170e62a450757be0cf192778f281` |

## Multiple live Browse continuations and deadline release, 2026-09-17

`session_open.c` replaces the single continuation with 64 continuation chains.
Each chain holds one live server continuation or one unfinished Browse,
BrowseNext or release, with its own page size and cumulative page, reference
and byte bounds, and each captured page gets a fresh `c<serial>` token. An
exposed Browse reserves a free chain or fails `busy` before an SDK request is
built. `browse_check.c` checks two live chains with distinct tokens, per-chain
admission and busy state, rejection of foreign and repeated tokens,
restoration after retiring queued work, a completed release freeing its chain,
the per-chain page ceiling, reservation of all 64 chains through the production
prepare path with a 65th `busy`, orphaning when sent work is retired, and
clearing on close.

`Native.Host` drops the single-chain flag. A Browse is admitted while fewer
than 64 continuations, deadline releases and Browse operations are live. A
stored continuation starts a timer at its original browse deadline. When that
timer fires, the host sends one bounded `browse_release` control and records the
reference in a bounded 64-entry expired set, so `next/2` returns
`deadline_exceeded` and `release/2` returns `:ok`. A failed or unanswered
release ends the generation. A token that duplicates a live continuation ends
the generation with `invalid_native_frame`. In `open62541_test.exs`, probe modes
return 64 live continuations and then `busy` (a release admits one more), a
duplicate token closes the owner, automatic release completes before `next/2`
reports the deadline, and a failed automatic release closes the owner. In
`native_paged_test.exs`, against the secure same-stack open62541 peer, two
continuations are live at once, one is released while the other advances,
another is released automatically after 100 ms, and complete collection
still succeeds on the same Session.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29:
RelWithDebInfo native CTest passes 204/204. macOS ASan/UBSan CTest passes 204 of
213, with the nine LeakSanitizer custody cases unavailable on macOS.
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 352 passed (10 doctests,
4 properties, 338 tests), 54 optional tests excluded and 95.3% coverage. The optional
secure suite with the lifecycle file passes 54/54 against both builds. WOP-F14
through F16 are not bound: their exact continuation bytes and lost-response
events need an injectable SDK service trace. Independent-peer BrowseNext is not
possible because asyncua 2.0.1 raises `NotImplementedError` for it.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/session_open.c` | `15ccee51ee2583d01b409a342d77fe9dc4d65fc729aa9d887ad6931c06c1638c` |
| `priv/native/session_open.h` | `e03bbc445fe1e397dd08d31e2978a2e7f011766c6c306fef4011f09416ec0999` |
| `priv/native/browse_check.c` | `05ef633979d931a79a4eda105b23ab9e031ecd2f9c06eba98392fb3af85113da` |
| `lib/wotex/opcua/native/host.ex` | `493fe79ab52587a9687149614601d78bed76d2ef671416637ae4bb8630108772` |
| `test/native/host_probe.c` | `3cf38634af740a5155a79ef0b929e0ab8e4267cd3f62a1fca549bdd06207e154` |
| `test/wotex/opcua/open62541_test.exs` | `e0e06d3a8adb094c027bb729ce0106c004256ff086443bf0686b580b2521dbca` |
| `test/interop/native_paged_test.exs` | `ab5e371aea7a673efbe91df006d7b79485c0ba8768cd16f07f0150f3639c4e63` |
| RelWithDebInfo `wotex_opcua_native` | `2e1927678d034acb6b4e47723a3efd0bef274e3270c9f1e6b19655157a98df1a` |
| ASan/UBSan `wotex_opcua_native` | `433fc7ffafff9d4ee2bf0e92ca607b77c395ad9c08bb0b3a180e7f7355c8c1f8` |
| native CTest log | `1b1d65df5cb2301100fe4f2dd6c177615952c617c8b14481f16c1e22f7aacdd2` |

## Runtime Property observation relay, 2026-09-17

`Wotex.OPCUA.Transport` now implements the Runtime `observeproperty`
callbacks. `Mapping` maps observation Form operations to an `:observe` message,
and `request/3` rejects every operation other than Property read and write
before I/O. `subscribe/4` rejects `subscribeevent`, input, a non-nil credential,
a dead or remote owner, a target mismatch, unknown `:subscription` keys and an
invalid `:max_queue_length` before starting a process. It then starts one
`Wotex.OPCUA.RuntimeRelay`, which opens its own Session through the configured
client and subscribes with itself as the 64-message native receiver. A watcher
kills the relay if the owner or the establishing caller exits before handoff.
When bound, the relay forwards frames within the owner's queue bound. On
overflow, a native error or an abnormal client exit it sends one error frame and
a `session_lost` or `transport_down` status. Cancellation and Session close share
one 900 ms release budget. `decode_frame/3` requires the six observation
metadata keys and projects the DataValue through `Value.native_result/1`.
`unsubscribe/4` validates the relay generation and releases it; with a non-nil
credential it still releases before returning `invalid_transport_context`.

`runtime_stream_test.exs` uses real `ConsumedThing` child specifications and an
injected streaming client. It covers projected delivery and stop,
`session_lost`/`transport_down` terminal loss without unsubscribe, owner-queue
overflow, owner death after binding, owner or caller death during establishment
(the relay is killed), establishment failures and deadlines, invalid requests,
frame decoding and handle validation, status redaction, and an Event child
failing without a Session. It binds WOP-X-F23: a short-lived worker establishes
the observation and exits normally, the final owner receives one notification,
and its death releases the relay. The actual Runtime `SubscriptionOpening`
reports `transport_down` when its callback worker is killed, so this binding
uses the transport boundary rather than a killed Runtime worker.

`native_runtime_stream_test.exs` uses the native persistent client and the
independent asyncua 2.0.1 peer. A Runtime observation child receives the
initial Double value and two written values with increasing sequence and a
stable client handle, and a ByteString child receives raw bytes. After stop the
peer's subscription and MonitoredItem counts are zero. Killing the Runtime
owner returns them to zero within 1,000 ms. A peer StatusChangeNotification
reaches the receiver as an error and `session_lost`, and the owner stops. An
Event child and a one-shot client configuration each fail without a peer
subscription.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29:
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 350 passed (10 doctests,
4 properties, 336 tests), 54 optional tests excluded and 95.7% coverage. The
first gate run for this slice failed one existing `host_test.exs` case: the
`late` probe ended with guardian status 128 (child signal) before readiness.
Five separate runs of that file and the full gate run recorded here passed; the
cause is not identified. With the peer environment described
above, `mix test --include interop --seed 0 test/interop
test/wotex/opcua/subscription_lifecycle_test.exs` passes 54/54 against the
RelWithDebInfo and macOS ASan/UBSan builds (native executable digests unchanged).
The I02 profile factory, I04 retry classes and I06 corpus are not executed.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/runtime_relay.ex` | `64a3823840ae1f0df47c397522050bec113079dfde5626061c73f6e87a00c713` |
| `lib/wotex/opcua/runtime_handle.ex` | `4f25b875ec43a92398d1f595ed27b1ec66c459cbedc27f8f8f4b093c17402b4c` |
| `lib/wotex/opcua/transport.ex` | `d6a1c3b3ae2f83f1180d65b817c9ef8055383114c77f4facd18a1b0f3b28467b` |
| `lib/wotex/opcua/mapping.ex` | `e1bbffdd57cb9fc451fd31e79ee2402ce7493a87fb19319ebf8456c06a389fdd` |
| `lib/wotex/opcua/value.ex` | `5b96ad14d42af1ce9c46fcbf1bcb200104046368fac4e140aa35fecd1350fc78` |
| `test/support/stream_client.ex` | `fbb941d04910dc47720f176b0ccec2a30d352a81ec91d4400d03641b4a723d35` |
| `test/support/nosec_credentials.ex` | `93f2647788ee2cab1d9f994349113aad896fa8e07df0a85fa52721e3d55a7500` |
| `test/test_helper.exs` | `ce5e1d8930afc61f7f50b6a1a825a1527d44b617eb18578153365b52d5309160` |
| `test/wotex/opcua/runtime_stream_test.exs` | `d86d2e93a183b8a79f601d9357b0510021dac0b2b5848f71d989d98d20afb455` |
| `test/interop/native_runtime_stream_test.exs` | `ab3d0ebda5ba6a22849aaee7a5e781fc36d30ac66955c9815171cb71803045ff` |
| `docs/specs/fixtures/native-contract-v1.json` | `5b43aae7c5d4313a75d4f597e741ca4a815eec34797bcd47d87a3f94bd8211ea` |

## Concrete Read health probe, 2026-09-17

`Wotex.OPCUA.health_check/2` accepts exactly `%{node_id: node}`. It sends one
validated Read through the selected client and returns `:ok` only when that Read
succeeds; any other probe shape returns `invalid_probe` before client I/O, and
`health_check/1` still returns `probe_required`. `port_test.exs` covers success,
an invalid NodeId, an extra key, and typed, untyped, invalid and raising client
results, each without effect. In `native_subscription_test.exs` a persistent
Basic256Sha256 Session against the independent asyncua 2.0.1 peer returns `:ok`
for the Double Variable, `remote_error` with a Bad status for a missing node, and
`:ok` again on the same Session.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29:
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 339 passed (10 doctests,
4 properties, 325 tests), 51 optional tests excluded and 95.5% coverage. The optional secure suite
with the lifecycle file passes 51/51 against the RelWithDebInfo and macOS
ASan/UBSan builds, whose executable digests are unchanged from the previous
section.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua.ex` | `b95cb0816f653441a9c2dd83558b956254fb26395fd4bca287022959a01ef59d` |
| `test/wotex/opcua/port_test.exs` | `784c27910694482f3252054754d9678759359464aaf7a4f67b3f747ee30ba9d4` |
| `test/interop/native_subscription_test.exs` | `c9687b66d8e01b9b6043d6c7fd7fb7c120779f1bbcc83f926c411af516a259be` |

## Subscription loss, owner death and a suspended overproducer, 2026-09-17

`Native.Host` no longer lets a failed credit write to an exited native process
replace the lines that process wrote before exiting. The lines are handled in
order, followed by the exit status. Owner death now fails each unanswered
request with `native_owner_lost` and its effect, and sends that error once to
each live subscription receiver. `host_probe.c` mode
`session_terminal_exit` writes a report and a terminal `receiver_overflow`
control, then exits while the host is suspended. `persistent_bridge_test.exs`
asserts that the report and then one `receiver_overflow` are delivered. With
the process fixture it asserts that owner death sends `native_owner_lost` once
to a subscription receiver and to a transmitted Write caller (unknown effect).
Both tests fail against the previous host. The same file's idle-generation probe
test no longer races its monitor against the probe's immediate output. That race
caused an intermittent `:noproc` DOWN reason, and ten further consecutive runs
passed 31/31.

`subscription_lifecycle_test.exs` runs against real peers.

- Owner death with two live independent-peer subscriptions: the host stops
  within 100 ms, its guardian and SDK processes exit and the peer's subscription
  and MonitoredItem counts reach zero within 1,000 ms. Each receiver gets one
  `native_owner_lost`.
- A peer `FailDeletes(1)` fault: unsubscribe returns `cleanup_failed`, the
  Session closes, the other receiver gets one `cleanup_failed` and the peer
  counts reach zero.
- Closing the same-stack peer: each of two subscriptions gets one
  `connection_failed` with a Bad status, and the native processes exit within
  1,000 ms.
- A suspended BEAM owner with four subscriptions while the same-stack peer
  (new `c` command) writes continuously: before the owner resumes, its mailbox
  holds exactly 16 report lines of at most 262,144 bytes, then one terminal
  `receiver_overflow` control and the exit status. The native processes are
  already gone. After resume the receiver gets the 16 reports and exactly one
  `receiver_overflow` per subscription, and the peer reports zero Sessions within
  1,000 ms. RSS is not measured because the native process exits first.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29:
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 338 passed (10 doctests,
4 properties, 324 tests), 50 optional tests excluded and 95.5% coverage.
RelWithDebInfo native CTest passes 204/204. With the peer environment described
above, `mix test --include interop --seed 0 test/interop
test/wotex/opcua/subscription_lifecycle_test.exs` passes 50/50 against both the
RelWithDebInfo and the macOS ASan/UBSan builds. Runtime final-owner handoff
(X-F23), live SDK Cancel acknowledgement counters and C09 repetition counts are
not executed.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/native/host.ex` | `e45e5fe9e8db46bebdd8a0413091cbe40d2d450f895172863e7022bd146e77be` |
| `priv/native/paged_peer.c` | `4c5d3715d518085d2e33c27effeb6b3dbf811304b6fb6b5b6106df24a2c5fa21` |
| `test/native/host_probe.c` | `27c5426d67bc139374ef83246a226e0af139ba5be6f0dab793ee8ddc094e7bb4` |
| `test/interop/secure_peer.py` | `36f5cad83d5112a35377f4d0b4ffc7360ac26fcf0cb2ad2620f82a8ae7e98d62` |
| `test/wotex/opcua/persistent_bridge_test.exs` | `edc404ff4e3825ae831f58a7bf3e0321257af1aa8e24f00ca7e439e801c816b9` |
| `test/wotex/opcua/subscription_lifecycle_test.exs` | `2a17ba910dc59b3b7c895680d51141f75d2103fa7ddd49f38c83141e0c2516b1` |
| RelWithDebInfo `wotex_opcua_paged_peer` | `90c0afc58a6b9bb5a2364afc6f00916c956875123cff57c3d00de18c4edf9af7` |
| ASan/UBSan `wotex_opcua_paged_peer` | `548c97ba8a8475a51dd3cd2c308af316ad20e799bf4fa30acb5894af5744a5e9` |
| RelWithDebInfo `wotex_opcua_native` | `a52f105354e141693710b807d4290bcc6911036876fc228d28b38523d2ac3034` |
| ASan/UBSan `wotex_opcua_native` | `b336153fce394d126a1a2904db5c1d30b69b194ae3647c03991533b98d66a482` |
| native CTest log | `32e00b25f6a696a724e8645bf84bbb53e9317e57792c11f88718fc46cc853be9` |

## Peer Republish, subscription loss and queue overflow, 2026-09-17

The independent asyncua 2.0.1 peer adds two test-only Methods.
`PublishFaults(withhold, discard)` makes the peer answer the next data-change
Publish with a keepalive. The peer keeps the withheld message for Republish, or
discards it when requested, and the Method returns the withheld and Republish
counts. `LoseSubscriptions` queues a BadTimeout StatusChangeNotification on
every subscription. Neither Method is part of the native client.

`native_subscription_test.exs` withholds one notification. The next fresh value
arrives, the native owner issues one Republish (the peer count increases by one)
and the receiver gets the withheld value and then the fresh value, each once and
in sequence order. When the withheld message is discarded, the empty Republish
ends only that subscription with one `sequence_gap`. The peer's subscription and
MonitoredItem counts return to zero and the Session still accepts a Write. A
peer StatusChangeNotification delivers one `subscription_lost` with status
`0x800A0000` and the peer counts also return to zero.

The same-stack C peer (`paged_peer.c`) adds a `burst` Double Variable, allows a
zero sampling interval and writes five consecutive values when it reads a `b`
byte. `native_lifecycle_test.exs` subscribes with queue size 2 and discard oldest.
One Publish then delivers value 4.0 with StatusCode `0x480` and `overflow: true`,
followed by 5.0 with status 0 and `overflow: false`. Both have the same sequence
and client handle. After unsubscribe and close the peer reports zero Sessions
and SecureChannels.

Commands and results on macOS arm64 with Elixir 1.20.2 / OTP 29:
`WOTEX_PATH_DEPS=1 mix check --no-retry` passes with 336 passed (10 doctests,
4 properties, 322 tests), 46 optional tests excluded and 95.5% coverage. RelWithDebInfo
native CTest passes 204/204. macOS ASan/UBSan CTest passes 204 of 213; the nine
`custody_leak_G01`..`G09` cases abort because LeakSanitizer is unavailable on
macOS. The optional secure suite, run as in the previous section, passes 46/46
against both builds. Lifetime expiry at a peer, a failed acknowledgement that
forces Session close at a peer and Linux cohorts are not executed.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/paged_peer.c` | `8ecb31b4c7042278fa08dd2d7712235359459d0a896713fd301f96a40466ced8` |
| `test/interop/secure_peer.py` | `8eee93f8751e12b3389b217c1b0c4c1603968f37d00d5e404e174ab79312bedd` |
| `test/interop/native_subscription_test.exs` | `767f5b2f8aac3ab7398dbaa877dfa35d9dae7910bdad6b4bdb6bf7a9508c716c` |
| `test/interop/native_lifecycle_test.exs` | `a6252acc51954f553ec6c9ceacf3e8921da35c5b7a08bc3e4a1b502a3af84d69` |
| RelWithDebInfo `wotex_opcua_paged_peer` | `3ff091c82b63de651f29d341884b0a4b8bdd744cba43be45eb1ec59b49b46eab` |
| ASan/UBSan `wotex_opcua_paged_peer` | `cc4756a2c7cd0a3ff948a912e01f6c8138a0de4902a70c750ec1388fd532f195` |
| RelWithDebInfo `wotex_opcua_native` | `a52f105354e141693710b807d4290bcc6911036876fc228d28b38523d2ac3034` |
| ASan/UBSan `wotex_opcua_native` | `b336153fce394d126a1a2904db5c1d30b69b194ae3647c03991533b98d66a482` |
| native CTest log | `600398cad6e847459041faff08c94efce88e733c089a30474f49bb0ccd650219` |

## Persistent native subscription delivery, 2026-09-17

`Wotex.OPCUA.subscribe/2` and `unsubscribe/2` validate the closed S04 request map
before I/O and call optional client callbacks; `Wotex.OPCUA.Subscription` is the
opaque, Inspect-redacted handle. `Wotex.OPCUA.Open62541` admits subscriptions on
persistent Sessions only. `Native.Frame` validates subscribe results and report
lines exactly, and `Native.Host` routes reports to monitored receivers as
recorded in WOP.13 X05.

`frame_test.exs` covers valid and malformed report, token and subscribe-result
frames. `port_test.exs` covers normalization of subscription client returns.
`persistent_bridge_test.exs` runs the production owner behind the injected
process fixture and deterministic probes. It checks ordered reports, closed-handle
cancellation, one terminal report, receiver overflow and death, Session loss,
concurrent cancellation with one native unsubscribe, a subscribe response after
the caller's deadline (cancelled with its report discarded), an unknown-token
report ending the generation, facade validation and one-shot rejection.

The independent asyncua 2.0.1 peer (Python 3.14.7) now exposes a Resources
method that returns its active subscription and MonitoredItem counts. In
`native_subscription_test.exs` a Basic256Sha256 Session receives the initial
value and two fresh written values once in increasing sequence with a stable
client handle. The counts are 1/1 while subscribed and 0/0 after cancellation.
Receiver death cancels only its own subscription, a two-message receiver bound
ends delivery with exactly one `receiver_overflow` and returns the counts to 0/0,
and a missing node returns `remote_error` without a server subscription.
`security_fault_test.exs` adds subscribe, report, count and unsubscribe to all
nine policy/token cells. X-F30..F38 stay unbound because their request-cancel
operation and peer continuation counts are not asserted.

Commands: `WOTEX_PATH_DEPS=1 mix check --no-retry` passes on macOS arm64 with
Elixir 1.20.2 / OTP 29: 336 passed (10 doctests, 4 properties, 322 tests),
42 optional tests excluded, 95.5% coverage. With a fresh peer started by
`secure_peer.py` and `WOTEX_OPCUA_INTEROP_CONFIG`, `WOTEX_OPCUA_NATIVE_EXECUTABLE`,
`WOTEX_OPCUA_NATIVE_GUARDIAN`, `WOTEX_OPCUA_NATIVE_PROBE` and
`WOTEX_OPCUA_PAGED_PEER` naming one build, `mix test --include interop --seed 0
test/interop` passes 42/42 against the RelWithDebInfo build and 42/42 against
the macOS ASan/UBSan build. Live Republish, peer-side subscription loss,
lifetime expiry against a peer and Runtime observation are not accepted.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua.ex` | `58c5fbbc710ab79499f34d77585d76a44d5af7e3dc0bb12b6f527e4de71598de` |
| `lib/wotex/opcua/subscription.ex` | `b33c2bbd0a8358a169b02b1f46a16dd658362cf4103c2643eaff2d80bbcc30d5` |
| `lib/wotex/opcua/client.ex` | `b51508a444b5f6b89bb95e2d6cca7efabda8bb25734e6e2a921fb8904580960d` |
| `lib/wotex/opcua/port_call.ex` | `55a4c67cfc601060399caf84b52ff1b53e892722daba84cef26dadef352edc81` |
| `lib/wotex/opcua/native/frame.ex` | `b43875bf207648e0a1f15e5ba8cdcbec8068d7607fa1fdaff6ab3dee75b727c1` |
| `lib/wotex/opcua/native/host.ex` | `66198181841bdc2023534e7a3af77a6ead498e6e6185f6e7bb8b70ae30faa584` |
| `lib/wotex/opcua/open62541.ex` | `b63cfc990bd85a63e825da99f4a48cfcca5ce5bf814c339940b866941053c968` |
| `test/wotex/opcua/persistent_bridge_test.exs` | `b410df76990588894e9d76168a19ebbca15280fab76b27280874bffaafec9c19` |
| `test/wotex/opcua/native/frame_test.exs` | `06c2099f16c9026211b9bd05bba1cc103edcff143396f1b23fd1d806b74f69e2` |
| `test/wotex/opcua/port_test.exs` | `4eb19312e994ed141dd862b0e791f3adc643aef09015c5db774bacc2aef5bfb4` |
| `test/native/owner_fixture.c` | `4f9d6c52949926621e3816b0bb4c65cb2e2e8b395a6a7f4da8c0359c2c63bc4c` |
| `test/native/host_probe.c` | `6f285d8aae621f1c129539aa07105e1832e5138efcda458b46cb02a59587b921` |
| `test/interop/native_subscription_test.exs` | `c19de44038c1484859e6d3e98a808e3ef35f837e1d7efb69227fa7d40a5ec54c` |
| `test/interop/security_fault_test.exs` | `1ecb20275d3dd9134e2ca85c43cb4ac59fd896c4be36951e5e377f5ab7807d49` |
| `test/interop/secure_peer.py` | `919e7de635150d4d7459967dfd7b8ad9f859fc4d3293db600ac26dc4dadaf9da` |
| `docs/specs/fixtures/native-contract-v1.json` | `24e519c756f189c0d55f4e95fc45c26e9451fb0088141d4f7b6f903ac6c0edf0` |
| RelWithDebInfo `wotex_opcua_native` | `a52f105354e141693710b807d4290bcc6911036876fc228d28b38523d2ac3034` |
| ASan/UBSan `wotex_opcua_native` | `b336153fce394d126a1a2904db5c1d30b69b194ae3647c03991533b98d66a482` |

## Native raw-service subscriptions, 2026-09-17

The native owner now admits `subscribe` and `unsubscribe` and emits subscription
reports after operation replies in each tick. `session_subscription.c`
implements them over raw CreateSubscription, CreateMonitoredItems, Publish,
Republish, DeleteMonitoredItems and DeleteSubscriptions services; the SDK's
high-level subscription manager is not used. The contract is recorded in
WOP.13 X05. The owner flushes each emitted envelope to its descriptor before
producing the next, so credited reports leave the bounded queue.

`wotex_opcua_owner_check` binds WOP-X-F21 with an injected report producer:
after a 16-message/262,144-byte grant and a suspended owner, exactly 16 reports
of 1,024 bytes are emitted, the queue peaks at 64 envelopes, the next report ends
the generation with `receiver_overflow` and no operation slot remains after
shutdown. It binds WOP-X-F29 with an injected deletion failure and failed Session
close: the generation ends with `cleanup_failed`, effect none, zero local
operations and a Session close attempt; remote deletion is not claimed.
`wotex_opcua_subscription_check` places Publish responses in a Session inbox
with an unconnected SDK client and runs production processing. It binds
WOP-X-F27 (Uncertain Boolean DataValue with both timestamps and a source
picosecond fraction projected exactly, with the 100 ns resolution metadata) and
WOP-X-F28 (the fixed noninteger revision accepted without rounding). Its matrix
covers subscribe parameter bounds, revision rejection, identical and conflicting
duplicates, a foreign client handle, a StatusChangeNotification, lifetime loss,
keepalive activity, a Bad acknowledgement status and a gap whose Republish cannot
be sent. Both checks pass in the RelWithDebInfo suite (204/204) and under macOS
ASan/UBSan (195/195 non-custody).

A manual exploratory run with the macOS ASan/UBSan executable against the
independent asyncua 2.0.1 peer opened a Basic256Sha256 Session, subscribed to the
Double variable (revised sampling 100 ms), received the initial report at
sequence 1, wrote 7.5 through the same Session, received it at sequence 2,
unsubscribed and closed. This was not an asserting test and is not acceptance
evidence. The optional secure suite still passes 38/38 and the complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 325 passed (10 doctests, 4 properties, 311 tests),
38 optional tests excluded and 95.5% coverage. The BEAM host does not route
reports yet, so no public subscription API, receiver bound, independent-peer
subscription assertion or live Republish evidence is accepted.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/session_subscription.c` | `21c23efa3fff8fb60ea5f100ee3481555b39f3cbeacc21d23a5fe5fe75ecae53` |
| `priv/native/session_internal.h` | `39bcf048977437ac47d80d77d4b40f55eb4dbca6499d85e19887e48f6c8941c4` |
| `priv/native/session_open.c` | `10dd5d93c01a10c0eff73b7818fd4a89f2649a1a0467e4d20bb1dabdbdfbd13c` |
| `priv/native/session_open.h` | `4a1f2106389eb7d24ce7baa2030bc4a4b2facf6c9d93a1e705d75c5fc95e72db` |
| `priv/native/subscription_rules.c` | `765285cda84939ab3e0e1c76f393074fe21cbb57384a4a914cc12d8857aebc42` |
| `priv/native/subscription_check.c` | `484587b106b50373c5a726bf7f43ea340a23104fda2c29b5946b9674795a16bf` |
| `priv/native/owner.c` | `f74f7cd637b0304cc2becb04b227f22ac7569416d390720954731795df3d8201` |
| `priv/native/owner.h` | `1ff18efdf569170d3eda4998671ad59966bd44fc2e6da3f70970d33fec973598` |
| `priv/native/owner_check.c` | `8900c38ae0456bd3b83c474111fee9dd9318720dccf60d57e67bac4cfd49421c` |
| `priv/native/output.c` | `7dc5b553601de7aad06c773a0d9d9320e241964bf4102ad6a6cb05549c871a8c` |
| `priv/native/main.c` | `ed8cafa05c939736c377aeeb131368cde1418eafe765abf145d768c0052150b6` |
| `native CTest log` | `8271b36fe77fe387091a99395980f54fe62cf67efd74f23fee95c32852982f69` |

## Native Publish sequence state, 2026-09-17

`publish_sequence.c` holds one subscription's notification sequence state. It
accepts 1..2^32-1 with wrap from 4294967295 to one, starts a new subscription at
one, keeps a 1,024-entry sequence/SHA-256 digest cache, acknowledges an
identical duplicate without delivery and rejects a duplicate with a different
digest. A gap of at most 100 missing messages starts ordered Republish recovery
for one held notification; each result must be available and carry exactly the
requested sequence before it is recorded, and the held notification is recorded
after the last one. Gaps above 100, unavailable or mismatched Republish results
and sequences older than the cache are terminal.

`wotex_opcua_publish_sequence_check` binds WOP-X-F24 through F26: a duplicate and
recovered gap deliver 1, 2 and 3 with one Republish for 2; an unavailable
Republish delivers 1 and ends with `sequence_gap`; and 4294967295 followed by 1
delivers both without Republish. The runner supplies Republish outcomes from
the corpus and never expected sequences. Its matrix covers zero, conflicting
duplicates, the 100/101 gap boundary, cache eviction after 1,024 entries,
stale sequences, out-of-order Republish and a wrapped gap. It passes under macOS
ASan/UBSan and in the RelWithDebInfo suite (199/199). The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 325 passed (10 doctests, 4 properties, 311 tests),
38 optional tests excluded and 95.5% coverage. No SDK subscription service,
Publish request, acknowledgement or report delivery uses this state yet.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/publish_sequence.c` | `9e08e3b1b56d68492681a59ce6f4001d416519ba8b404dbc00ea0d17604214f4` |
| `priv/native/publish_sequence.h` | `10b7ed714b9f8ee801270edc6b3fa83da2f70a35125622a8dde5dce8be32aa30` |
| `priv/native/publish_sequence_check.c` | `e682bd38e25ae4b3bf6900ae86874668663737ce6319c7c45784daf35b1299aa` |
| `priv/native/CMakeLists.txt` | `4a5ca1988e917682804838eec5adedb956c88e94c25e6c065a77ff050653addb` |
| `native CTest log` | `5ac6e600e39ef8aef24113dacf6b5f5c5265af179657a98f26d3d20e5967a030` |

## Secure policy, user-token and rejection matrix, 2026-09-17

The test-only asyncua 2.0.1 peer now offers Basic256Sha256,
Aes128_Sha256_RsaOaep and Aes256_Sha256_RsaPss SignAndEncrypt endpoints with
anonymous, username and X509 user-token policies. Its fixture user manager
admits anonymous users, one username/password and one generated user
certificate. The generator also writes an unregistered client-authentication
user certificate, an expired CRL, an unrelated key and an untrusted CA. Named
variants reuse those credentials to present an expired or wrong-host server
leaf, offer only Security None, or offer only anonymous tokens.

Opening failures now retain the SDK connection status. User access, identity
token and user signature rejections are `authentication_failed`; certificate,
security-check, policy and mode rejections are `certificate_invalid`; other
statuses are `connection_failed`. The owner no longer replaces a Session-step
failure during opening with `invalid_response`.

`security_fault_test.exs` runs each WOP-X-F30 through F38 policy/token cell
through the public persistent client: Read, Write, readback, Method Call,
child Browse, restore and close, with the host reaped. Subscribe and cancel are
not executed, so those corpus cells remain unbound. A wrong password, an unknown
user and an unregistered user certificate fail activation with
`authentication_failed` and status `0x801F0000`, without anonymous fallback.
WOP-X-F39 through F47 fail with effect none and no Session. Expired and
wrong-host leaves, a wrong server application URI, an untrusted CA, a revoked
leaf, an expired CRL and a mismatched private key are rejected by credential
preflight before network access (`certificate_invalid`). An anonymous-only peer
rejects a username token with `authentication_failed` and status `0x80210000`.
A Security None-only peer and a peer presenting an unpinned leaf neither answer
nor close the OpenSecureChannel request, so both end at the 2,000 ms open
deadline with `deadline_exceeded` and no Session.

The optional secure suite passes 38/38 with the RelWithDebInfo and macOS
ASan/UBSan executables, and native CTest passes 195/195. The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 325 passed (10 doctests, 4 properties, 311 tests),
38 optional tests excluded and 95.5% coverage. This evidence does not accept
subscription or cancellation cells, tampered or replayed secure traffic,
server-side cleanup counters for the independent peer, token-policy
encryption algorithm assertions or the Linux cohort.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/session_open.c` | `d9833e18f30985fb6d2cc06b09924e20600a6c9746b3113b91291f16a0fc9f65` |
| `priv/native/owner.c` | `30455c937d6460b3b8e1db7c95ab2e584d6fbc5055c2c7324fa0c250942ff0b7` |
| `test/interop/secure_peer.py` | `aaad6b3a7881957c69133a2a40080704011ef50cf70585b7e4ffb90940215d89` |
| `test/interop/security_fault_test.exs` | `a2c123520c81da4b1d363cffecdfa7ed28baad11fca81bdc7e3f4fc91c3c8579` |
| `docs/specs/fixtures/native-contract-v1.json` | `bb1767c1bf514a282392e909a521fc8d7884c45c4539cf05a1a869dc63dbe4ff` |

## Multi-process public client and Session lifecycle counters, 2026-09-17

`Open62541.request/3` now admits Read, Write and Call from any process through a
persistent handle; the host monitors each caller and bounds admission at 64.
Browse and disconnect remain owner-only because they own continuation and
Session cleanup. Against the independent asyncua 2.0.1 peer, 32 processes share
one public persistent client with interleaved Method Calls and ByteString Reads
whose outputs match their own inputs, while non-owner Browse and disconnect
return `invalid_native_handle`.

`paged_peer.c` now prints current and cumulative server Session counts, Session
timeout and abort counts and current SecureChannels for each `s` byte on its
input. `native_lifecycle_test.exs` uses those counters with the production
executable and guardian. An explicit close removes the Session and channel
within 500 ms of its acknowledgement with a 60,000 ms Session timeout and no
server timeout. The test measures one full secure activation, then kills the
host owner at 0, 1/8, 1/4, 1/2, 3/4 and 7/8 of that duration and once after a
successful open. Each case reaps the host and guardian within 1,000 ms, releases
the server channel within 1,000 ms and returns the server Session count to zero
within 5,000 ms with a 1,000 ms Session timeout; the cumulative Session count
must increase across the kills. Observed local runs activated in 165–186 ms and
created three Sessions during the kills. One RelWithDebInfo run recorded one
server Session timeout and the others none, so a Session created before owner
loss may be deleted cooperatively or expire on the server; the test accepts
either and asserts no leaked Session. A read, an unknown-namespace validation
failure and a health read keep the real Session active until an explicit close.

The optional secure suite passes 18/18 with both the RelWithDebInfo and macOS
ASan/UBSan executables. The complete `WOTEX_PATH_DEPS=1 mix check --no-retry`
gate passes on macOS arm64 with Elixir 1.20.2 / OTP 29.0.4: 325 passed
(10 doctests, 4 properties, 311 tests), 18 optional tests excluded and 95.5%
coverage. The same-stack counter peer is not independent-stack evidence, and no
server-side Cancel or subscription cleanup counter is accepted.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/open62541.ex` | `a0b3f4ca8571ede6baba634582bc693d42cec0dd00e46f56cd172277a4392228` |
| `priv/native/paged_peer.c` | `6d4c771241374149578bf1a60bf5bd474c0affd7f6d2524f2e4f6472817ffa17` |
| `test/interop/native_lifecycle_test.exs` | `122c76549000f76c06f4252add911377697527d882605bb7e833ebcf2df1b14b` |
| `test/interop/native_secure_test.exs` | `837e1670eff658460add6094d8bd4f51e9715a2e2c9791cd580766e5e711a2e4` |

## Native namespace projection for identity values, 2026-09-17

The pinned SDK decodes every NodeId namespace index, including the NodeId inside
an ExpandedNodeId and an encoded ExtensionObject type identity, from the server
table into its client-local table, and maps it back on encode. It does not remap
QualifiedName indexes, and it resolves an ExpandedNodeId URI found in its table
to that local index. The Session now samples the SDK table when it becomes ready
and projects decoded Read DataValues, Call outputs and Browse
ReferenceDescriptions back to server NamespaceArray indexes through exact URI
equality; Write values and Call inputs are localized the same way. Indexes
outside the server table use the SDK's reversible `65535 - index` rule and fail
when that would collide with a local entry. Server indexes from 65536 minus the
SDK table size to 65535 are indistinguishable after SDK decoding; this is a
recorded SDK boundary, not a supported identity. Projection failure is a
request-scoped `invalid_response`, or terminal when a live Browse continuation
would be lost. NodeId, ExpandedNodeId, QualifiedName and opaque ExtensionObject
Variants are now admitted for native Read, Write and Call, validated by
`Native.Frame` and projected to exact native envelopes by the public client.

`wotex_opcua_namespace_check` builds an unconnected SDK client whose local table
orders two URIs opposite to the server table and asserts both directions for a
NodeId, out-of-table and colliding indexes, a NodeId array inside a DataValue,
URI identities, encoded and decoded ExtensionObjects, ReferenceDescription fields,
unchanged QualifiedName, rejected nested Variants and a URI missing from the
server table. It passes in the RelWithDebInfo suite (195/195) and under macOS
ASan/UBSan (186/186 non-custody). ExUnit adds exact native request envelopes and
result validation for all four types through a deterministic probe, plus
malformed-envelope rejection in `frame_test.exs`. The independent asyncua 2.0.1
peer now exposes writable NodeId and QualifiedName variables; through a secure
public persistent client the test reads the NodeId `ns=2;s=value` and the
QualifiedName in namespace 2, writes new values, reads them back and restores
them. The optional secure suite passes 14/14 with the normal and sanitizer
executables. Both servers keep identical server and SDK namespace order, so
reordering itself is proven only by the native check. The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 325 passed (10 doctests, 4 properties, 311 tests),
14 optional tests excluded and 95.6% coverage. One-shot legacy result shapes
still reject structured identity values.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/session_open.c` | `7360ccd5a215aa486d1a4fb19648e2ccf5e161419eb8dd702ba068cb36a7ee56` |
| `priv/native/session_open.h` | `d29bc9ca10228f976b8c690abef8953ef7b81b48b77bc23b2f4ac7d2b595e0fd` |
| `priv/native/namespace_check.c` | `f429e043947934a9563e731defdb15d800c4af9e263b5457d391fa10ec3aceb6` |
| `lib/wotex/opcua/native/frame.ex` | `1f107e77c516ee60b032f1fb5d2037a25602a73eaf7997f83fb0c3675f1229ca` |
| `lib/wotex/opcua/open62541.ex` | `01e4986a65c3d5535ad66330177c860a1fcb14b0a8afe2605c9eb9a40de67cd1` |
| `test/interop/secure_peer.py` | `883045d467c60c4490cfa006ba90f172e4729ed7f007d6bd46850da298c9fe7d` |
| `test/interop/native_secure_test.exs` | `27b804f74cb2f62bc25b942a0824db71881de29d8399cd58506b0b95c312382a` |
| `test/native/host_probe.c` | `757d582eed003695647ef4eac9d142ed2e5902310e477276a59c21e7e0e9cd8c` |
| `native CTest log` | `52612573bbf6655ac12b86eb4a0dca43fc571481af5a569643ce312b6952b438` |

## Concurrent native host admission, 2026-09-17

`Native.Host` now admits at most 64 outstanding requests. Read, health, Write
and Call may come from any process; each caller is monitored, while `open`,
`close` and Browse handles stay owner-only. Output chunks are split into
complete LF-terminated lines of at most 131,072 bytes, classified by
`Native.Frame.classify/2` and correlated by request identity. Each validated
line returns one message and its bytes as credit. A request-scoped native
failure is delivered and the Session remains open. A caller timeout or caller
death retires the request locally and sends one `cancel` control with a
1,000 ms budget; its missing or foreign acknowledgement ends the generation.
A terminal control, unsolicited or oversized output, a response or terminal for
another generation (`response_mismatch`), native exit or a failed close ends
the generation and answers every unanswered request once. A sent Write or Call
keeps unknown effect; a request still in the host mailbox when the host stops
reports none, and a call timeout keeps unknown effect for a mutation. The owner
receives one asynchronous error only when no caller was waiting. Excess Browse
results and an expired browse deadline now release the live continuation and
keep the Session; an unowned raw continuation still closes it.

`test/native/owner_fixture.c` runs the production `owner.c`, output queue and
IPC parser as a guardian-owned process with an explicitly injected service
selected only by request node identity. `persistent_bridge_test.exs` uses it
to assert 32 concurrent callers with distinct values, the WOP-X-F20 64-request
bound with `busy` and close from the control reserve, timeout and caller-death
cancellation counters, request-scoped Bad status and invalid values,
per-request effects on Session loss, WOP-X-F22 owner death during Session
activation with cleanup inside 1,000 ms, an expired activation, a suspended host
and dead-owner calls. Deterministic `host_probe.c` modes bind WOP-X-F51, F56 and
F57 (including a queued mailbox Write), coalesced and byte-split responses,
oversized and unsolicited output, terminal or failed close, a foreign cancel
acknowledgement and Browse chain recovery. `frame_test.exs` binds the
WOP-X-F17 owner-side deadline translation and classification cases. Existing
host and client tests now assert that request timeout sends cancellation and
that excess or expired Browse results release instead of closing.

The optional secure suite passes 13/13 against the independent asyncua 2.0.1
peer and same-stack paged C peer with both the RelWithDebInfo and macOS
ASan/UBSan native executables. It now includes 32 concurrent Read and health
callers on one secure Session and asserts that Bad Read and rejected Write keep
the Session usable. The previously failing public-client case passes because a
typed Browse that exceeds `max_references` without a continuation no longer
closes the Session. The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate
passes on macOS arm64 with Elixir 1.20.2 / OTP 29.0.4: 323 passed
(10 doctests, 4 properties, 309 tests), 13 optional tests excluded and 95.5%
coverage, with `Native.Host` and `Native.Frame` fully covered.

The public `Open62541` facade still accepts service calls only from its owner
process, so C09 multi-caller public-client stress is not accepted. WOP-X-F19's
Runtime `permanent` class, F21 report overflow and F23 Runtime handoff remain
unbound, as do live SDK Cancel acknowledgement counters and independent-peer
cancellation.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/native/host.ex` | `4151bf1952685be1774e5cc06d4666e62aa64c6740b6b2d6d7544c1c1abb573f` |
| `lib/wotex/opcua/native/frame.ex` | `18ad916a25b0bc8f1092e340e104b91e804f8a6cccea4efc02d106fc3610d19f` |
| `test/wotex/opcua/persistent_bridge_test.exs` | `0bdadbbe04faf5001830d9167fc1c9973548275503de4f24318b03b3c41104ba` |
| `test/native/owner_fixture.c` | `38852f327b17e0925e4fd65589be28c8aeb94e19e4cd25e036a013a612d592b9` |
| `test/native/host_probe.c` | `7373b4c2d698a2d45fe5848d4bea0b2d0b0e725715ab79bdefc47ca128eecb1d` |
| `test/interop/native_secure_test.exs` | `c6c675c5cc0648f13c41ee5872f512ac98468a2d206247e454cb012826e7b303` |

## Multiplexed native process owner, 2026-09-17

`priv/native/owner.c` replaces the single-flight loop in `main.c`. It admits at
most 64 application operations, validates and copies each request without
protocol I/O, and dispatches queued work in admission order on the next loop
tick with a finite SDK timeout hint and a request handle below 100,000. Each
admitted request receives exactly one success or request-scoped failure.
Validation failures, a service before `open`, expired admission, `busy`, Bad
Read/Write/Call/first-page Browse statuses and `deadline_exceeded` keep the
Session usable. Malformed frames or envelopes, credit violations, duplicate
outstanding IDs, Session or channel loss, BrowseNext/release faults and cleanup
failure remain terminal. `cancel` and `close` use separate control admission.
`cancel` answers an unfinished target with `canceled`, keeps unknown effect for
a sent Write or Call, sends the SDK Cancel service through the asynchronous
service API and returns `{target_id, canceled}`. Retired sent work keeps its
slot until the SDK callback matching both slot and request ID releases it. A
retired continuation-owning Browse, BrowseNext or release closes the Session
because server continuation state could remain unowned. `health` uses the Read
path. The SDK service stores per-slot requests and waits before reporting
`open` until the SDK's own namespace table contains every server URI. The loop
also reads input when `poll` reports `POLLNVAL`, which a device-file stdin
produces on macOS; before this change such an EOF was never observed.

`wotex_opcua_owner_check` drives the production owner, output queue and IPC
parser with an explicitly injected service and binds WOP-X-F17 through F20,
F49, F50 and F52 through F55 in `native-contract-v1.json`. F17's native deadline
uses the same arithmetic as `Native.Frame.admission/5`; the owner-side
translation is bound separately in ExUnit. Its matrix covers every split of two
coalesced request lines, FIFO dispatch and distinct request handles, request
failures, Bad status, dispatched deadline expiry with protocol cancellation and
held slot release, queued expiry without I/O, duplicate IDs, Session loss with
an unknown terminal effect, clean and truncated EOF, malformed and oversized
input, and receiver overflow with no credit. The real-process build test now
asserts request-scoped `invalid_request` and `unsupported_protocol` failures
without process exit, plus terminal deadline admission for an expired `open`.
`browse_check.c` covers token admission, queued BrowseNext retirement restoring
the continuation and orphaning after dispatched retirement.

The incremental RelWithDebInfo native CTest suite passes 194/194. A macOS Debug
build with `-DWOTEX_SANITIZERS=ON` passes 185/185 non-custody CTests under
AddressSanitizer/UndefinedBehaviorSanitizer; `sanitizer_options.c`, linked only
into that build, disables symbolizer discovery so the guardian's no-stderr rule
does not reject the instrumented executable. The optional secure suite against
the independent asyncua 2.0.1 peer and same-stack paged C peer passes 11 of 12
tests with both the normal and sanitizer executables; the remaining failure is
the pre-existing BEAM host Session closure after a typed Browse exceeds
`max_references: 1`. The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate
passes on macOS arm64 with Elixir 1.20.2 / OTP 29.0.4: 301 passed
(10 doctests, 4 properties, 287 tests), 12 optional tests excluded and 95.0%
coverage, including the fresh pinned native build and CTest.

The BEAM host still submits one request at a time and stops on any native
failure, so no public concurrency, cancellation, caller-death cleanup or
terminal per-request effect mapping is accepted. Live SDK cancellation, receiver
overflow from a report producer, owner death during open and Runtime handoff
(F21 through F23) and F51, F56 and F57 remain unbound.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/owner.c` | `f9fc86de2df620af7d69bd461db875a00effa5e9f44975970607818966c19faa` |
| `priv/native/owner.h` | `49d47bc103012dde6b465937d37603f227879348519f3a433559f3a6988c78a8` |
| `priv/native/owner_check.c` | `fc6f8997dea99ee2d4dab6ca16fffe3e3710bb5583b1d80a33e65399685964b5` |
| `priv/native/main.c` | `2e83285a6ae601ccaf67e9e9aab5524062308339448c064f808fccacda66b2e4` |
| `priv/native/session_open.c` | `0072f6cab69eb35acd25b1b7309bd288dde6d240346c0e8eb943603bea0449f1` |
| `priv/native/session_open.h` | `91a2d0b0cdff3b682a4a1f8da420c1149e90378ab0ba6f67c87b0c6e13b93f48` |
| `priv/native/browse_check.c` | `90697dd96a2ba3087d4cf3d644e201b19fc86d93adaecd4b3ada84487797c5ee` |
| `priv/native/sanitizer_options.c` | `4f00dc281b1404be61b25b2f0f474bffa54b4df0bb449cf8074331716ec055ba` |
| `priv/native/CMakeLists.txt` | `3b03e90710324df33991304918ca3bcb606365fc833004db1743454da4ef994c` |
| `docs/specs/fixtures/native-contract-v1.json` | `002a0b6876fda6aa0acd870e44c9d94b2b77a4f51d3d61c6563bef187804900b` |
| native CTest log | `7a1b180825ee0cc358919dad4dabec6d6f5d3db159ce028062538425f04becbd` |

## Bounded native output queue, 2026-09-17

`priv/native/output.c` now owns normal native output. Each complete
LF-terminated envelope waits in a queue bounded to 64 frames and 1 MiB,
including a partially written frame. It spends one message credit and its
encoded bytes only when its first byte is written to the nonblocking pipe, so
no normal byte is emitted without credit. Replenishment must follow the exact
sequence, generation and consumed amount, and outstanding credit cannot exceed
16 messages or 262,144 bytes. Ready and one terminal control share the
4096-byte allowance; a terminal follows an active partial envelope intact and
discards queued envelopes that have not started. `main.c` routes all existing
responses and controls through this queue, polls stdout for writability and
drains already admitted output for at most 100 ms before and after Session
cleanup. Temporary backpressure retains state; other write failures end the
process.

`wotex_opcua_output_check` asserts credit gating and replenishment, replay,
foreign, skipped and wrapped sequences, the 64-frame and 1 MiB bounds,
malformed envelopes, a 131,072-byte frame split by real pipe backpressure
followed by an intact terminal, the shared control allowance and a closed
descriptor. It passes under the RelWithDebInfo CTest target and under macOS
AddressSanitizer/UndefinedBehaviorSanitizer (`cc -fsanitize=address,undefined`).
The incremental native CTest suite passes 183/183. The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 301 passed (10 doctests, 4 properties, 287 tests),
12 optional tests excluded and 95.0% coverage, including the fresh pinned native
build and CTest.

The optional secure suite against the independent asyncua 2.0.1 peer and the
same-stack paged C peer passes 11 of 12 tests with this executable. The failing
public-client case also fails with the unchanged `9426fb9` executable: after a
typed Browse exceeds `max_references: 1`, the BEAM host closes the Session, so the
test's following Write returns `native_process_terminated`. This queue does not
accept concurrent operations, cancellation, report buffering, receiver overflow
through a live producer or any `native-contract-v1.json` case.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/output.c` | `27dd3435ce76172fb1e866611b8d1d770fae7d536072ec47cae226fe098094f5` |
| `priv/native/output.h` | `ae2eaaf4b10b5d18f154fb426f07571343495ede1f296735bccb96b0653e2dc4` |
| `priv/native/output_check.c` | `63202944c9138a2a79a33030e8b7a18ece0c4b9a4b12bbaa9af5e591dfbd41bb` |
| `priv/native/main.c` | `ed9baa3a0e2599e74c0fc9139aedf746c6aac9e823731039373630ed3806003b` |
| `priv/native/CMakeLists.txt` | `99637121401cdb41fbb6ddac887e47edb143ee5a5b9a90f23024681d48cf45db` |
| native CTest log | `5843c40fd12e778b988a6169818dce03b3b9d8f41247ef6593978e992dfad5cb` |

## Native-only runtime boundary, 2026-09-17

The first-party `Wotex.OPCUA.Asyncua` client, `priv/opcua_bridge.py` and their
adapter-specific tests are removed. `Wotex.OPCUA.Open62541` is the remaining
first-party runtime client; callers still select it explicitly and provide the
native executable, guardian and security configuration. The independent
asyncua peer remains under `test/interop` with a test-only requirements lock.
Upstream open62541 generation still uses Python at build time. No Python source
is included in the runtime package.

`WOTEX_PATH_DEPS=1 mix check` passed 301 checks (10 doctests, 4 properties,
287 tests), with 12 excluded, and met the 95.0% coverage floor. Strict Credo
reported zero findings. The new close-response regression confirms that native
cleanup preserves typed errors and rejects malformed acknowledgments; the
configuration regression rejects an unsupported authentication selector.
The older native build, software peer and Linux matrix receipts below are
source-bound and do not automatically attest this changed tree.

## Secure same-stack BrowseNext and release, 2026-09-16

`priv/native/paged_peer.c` is an uninstalled C-only secure test peer built from
the pinned open62541 SDK. It binds loopback, uses the existing generated
certificate/CRL fixture, advertises the fixture server URI and forces one
reference per Browse result. Its stdin owner pipe ends the server when the test
Port closes. The native build receipt now hashes this source and the earlier
`browse_check.c` token-state source.

`test/interop/native_paged_test.exs` opens a Basic256Sha256 SignAndEncrypt
Session through the production executable and asserts a typed first page,
BrowseNext, explicit release, consumed-handle rejection, complete `Browse.all/3`,
and three-child projection through both persistent and one-shot public clients.
The pinned server returns one empty Good BrowseResult for release of one
continuation; the C callback previously expected zero results and closed with
`cleanup_failed`. It now checks the actual one-result shape. The optional
same-stack interop test passes 1/1, and no peer remains after Port closure.
The test uses no Python process for the peer or production client. It is
same-stack wire evidence, not independent implementation interoperability or
proof of multiple concurrent continuations, release counters, and the full
WOP-N03/N04 failure matrix.

## Multi-page child-list compatibility, 2026-09-16

The selected native client now accumulates bounded forward
HierarchicalReferences pages into its existing ordered NodeId-list result.
Persistent requests use the caller's Session. One-shot requests open one
temporary Session, collect all pages there and close it before returning.
The total child limit is 256; duplicate references retain duplicate NodeIds.
An Uncertain page or an invalid later-page ExpandedNodeId fails without
returning an incomplete list and releases a live cursor or closes the owner.
The original request deadline applies across opening, pages and completion.

Deterministic C response fixtures pass a three-page sequence in persistent and
one-shot modes, plus later-page invalid identity and Uncertain status cleanup.
The focused public client suite passes 27/27. The independent asyncua peer
does not implement server-side BrowseNext, so this is not multi-page wire
interoperability or full WOP-N04 acceptance.
The final local `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes with
302 tests, 12 optional tests excluded and 95.0% coverage. Compiler, format,
Credo, Dialyzer, docs, audits, native CTest and isolated package/archive
checks pass. No production Python path was added.

## Persistent typed Browse handles and bounded collection, 2026-09-16

`Browse.references/3` now opts into a native continuation only for an owned
persistent Session. The BEAM host replaces each local C token with an opaque
`Browse.Continuation` reference bound to that host and generation. `next/2`
consumes the old reference, `release/2` sends bounded release, and `all/3`
collects complete pages in server order. The original absolute deadline and
cumulative page/reference/encoded-byte limits survive each hop; expired or
over-bound work closes the Session. An Uncertain page fails `:incomplete_browse`
and releases its live cursor. A release protocol failure closes the host.

The deterministic C response peer exercises an empty first page, two later
pages, reused/foreign handles, early release, `all/3`, Uncertain status,
page/reference caps, original-deadline expiry and release failure. The focused
public client suite passes 22/22. The native C owner still holds only one live
continuation per Session, and the independent asyncua peer does not implement
BrowseNext. These fixtures do not prove a peer wire exchange, multiple live
continuations, one-shot child pagination or full WOP-N03/N04 acceptance.
The final local `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes with
299 tests, 12 optional tests excluded and 95.0% coverage. Compiler, format,
Credo, Dialyzer, docs, dependency audits, native CTest and the isolated
package/archive checks pass. No production Python path was added.

## Native Browse continuation owner groundwork, 2026-09-16

The C Session owner now has an internal opt-in for one live Browse
continuation. It copies the server point into C-owned memory, gives each page
a fresh local token even if opaque bytes repeat, and has asynchronous
`browse_next` and `browse_release` service paths. It caps each page at the
requested size and cumulative pages/references/binary results at 64/4096/1 MiB;
failure closes the Session. Existing public Browse calls do not opt in and
still close on any continuation. The BEAM host rejects returned continuation
tokens, so no public pagination or token ownership is claimed.

The BEAM response frame now admits only canonical native `c` plus uint64
continuation tokens and exact null release responses. The host still closes
on a returned token, which a deterministic C response peer verifies before
any token can escape. Malformed or forged token strings fail frame validation.
Focused frame and host tests pass 30/30. These tests do not establish a
server-side BrowseNext wire exchange or public handle ownership.

The native token-state CTest passes reused bytes, foreign token and opt-out
cases. The full native CTest passes 182/182; the existing independent secure
peer suite passes 11/11 and confirms the public fail-closed path. That peer
ignores the requested page size and has no server-side BrowseNext, so it cannot
validate the new wire path. A peer with continuation/release counters, BEAM
handles, original deadline, multiple live tokens and cleanup-failure behavior
remain required for WOP-N03/N04. The local
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes with 293 tests,
12 optional tests excluded and 95.1% coverage; documentation, audits,
native build and package/archive checks pass.

## Persistent native typed single-page Browse, 2026-09-16

`Browse.references/3` now validates its strict finite filters before I/O and
returns a `Browse.Page` containing all seven typed ReferenceDescription fields
in server order when the selected persistent native Session receives a complete
page. A C response fixture checks local and remote ExpandedNodeIds, unknown
local namespaces, duplicate reference preservation, excess references and
invalid options; the independent Basic256Sha256 peer
confirms typed references for both a Variable and Method, plus a
`max_references` limit failure. Eleven optional secure-peer tests passed.
The native executor still closes the Session on a continuation or oversized
server page. BrowseNext, release, cumulative limits and typed handles remain
unimplemented; N03/N04 are not accepted.
The final local `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passed with
293 tests, 12 optional tests excluded and 95.1% coverage; compiler, Credo,
Dialyzer, documentation, audits, native custody, package and isolated archive
checks passed. The first full run exposed a 94.9% coverage shortfall; the
duplicate-reference and `max_references` boundary assertions closed it.

## Native Runtime ByteString array Write, 2026-09-16

The Form mapper accepts an explicit typed ByteString array with no inferred
type, validates it through the bounded pure Variant codec and emits base64 for
the older JSON boundary. Only the selected native Transport decodes those
elements back to bytes before a typed Write. A C fixture checks both an
embedded-zero/non-UTF-8 element and an empty element in the native request.
The independent Basic256Sha256 peer accepts the Runtime Form Write, then the
Runtime Form Read returns the same ordered BEAM binaries. The prior array value
is restored. Eleven optional secure-peer tests passed. The older Python
adapter rejects typed array Writes before process startup; no production
Python path was added. General array types and full Runtime integration remain
open.
The final local `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passed with
292 tests, 12 optional tests excluded and 95.0% coverage. Compiler, Credo,
Dialyzer, documentation, audits, native custody, package and isolated archive
checks passed. Two earlier runs exposed coverage below the 95% floor; explicit
dimension, malformed/oversized bytes and null-array boundary assertions were
added before the passing gate.

## Native Runtime ByteString array read, 2026-09-16

The Runtime value adapter decodes flat ByteString array elements from the
selected native one-shot Read to ordered BEAM binaries, preserving null and
empty values. It rejects malformed envelopes, more than 1024 elements, an
element above 64 KiB or an aggregate above 1 MiB. The independent secure peer
accepted a typed array Write, then Runtime Form read back `<<0, 255>>` and
`<<>>` before the test restored the original array. Eleven optional secure-peer
tests passed. General typed-array and Runtime integration acceptance remains
open.
The final local `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passed with
291 tests, 12 optional tests excluded and the required 95% coverage floor;
compiler, Credo, Dialyzer, docs, audits, native custody, package and archive
checks passed. The first run identified a readability issue in the new decoder;
it was corrected before the passing gate.

## Native Runtime ByteString Form handoff, 2026-09-16

The existing Form mapper encodes a ByteString as base64 for the older JSON
bridge. `Wotex.OPCUA.Transport` now decodes that already validated payload
only for the explicitly selected `Open62541` client, preserving the raw bytes
expected by its typed Write request. A deterministic C response fixture checks
that the native request contains the original `AP8=` byte envelope for
`<<0, 255>>`, rather than the base64 of those four ASCII characters. An
independent Basic256Sha256 peer exposes a writable ByteString scalar. Through
Runtime Form selection, the native one-shot client reads its initial value,
writes `<<0, 255>>`, reads back exact bytes, and restores the initial value.
Eleven optional secure-peer tests pass. The Python code in this slice is solely
the independent test peer; no production Python path was added.
The full local `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passed with
291 tests, 12 optional tests excluded and 95.0% coverage. The first run hit
a transient process-custody timing failure during the concurrent native build;
the isolated custody suite passed 19 tests and the unchanged full gate passed
on retry.

This is one WOP-I01 integration cell. The profile factory, complete Runtime
matrix, typed Browse pagination, subscriptions and Python-adapter removal
remain open.

## Native one-shot compatibility success shapes, 2026-09-16

The explicitly selected native client now maps successful one-shot Value Read
to the older `{type, value, status}` envelope, Write to `"written"`, and Method
Call to nil, a single value or an ordered value list for zero, one or multiple
outputs. ByteString values retain the older `{type: "ByteString", base64}`
envelope, including array elements. Persistent mode still returns validated
native DataValue, Write status and Call result maps. The independent secure peer
exercises one-shot Read, Write, Call and ByteString array projection without
launching the packaged Python adapter; a deterministic C response peer tests
all three Call arities. The one-shot Read envelope also passes the Runtime
`Value.result/1` mapper. Absent, LocalizedText and multidimensional values
without an older JSON shape fail as `unsupported_type`. Ten optional secure-peer
tests pass.

The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64
with Elixir 1.20.2 / OTP 29.0.4: 290 passed (10 doctests, 4 properties,
276 tests), 11 optional tests excluded and 95.1% coverage. Documentation,
dependency audits, native build and package/archive checks pass.

This is successful-result compatibility only. Error/status, full lifecycle,
typed Browse pagination, subscriptions and policy/token interoperability remain open.

## Native single-page Browse and child projection, 2026-09-16

The production open62541 executable now sends one asynchronous service-level
Browse with an explicit 1..256 page size and full result mask. It retains the
server-order ReferenceDescriptions and returns all seven typed fields through a
strict BEAM frame validator. A page above the requested size or a server
continuation closes the Session and returns an error, so the public client never
claims an incomplete child list as complete. The explicitly selected public
`Open62541` client projects local child NodeIds in persistent and one-shot
Sessions; remote ExpandedNodeIds and unknown local namespaces fail explicitly.

The independent Basic256Sha256 peer passes complete-page Browse, Value
Read/Write/readback, Call, ByteString array readback and fail-closed server page
limit checks: ten optional secure-peer tests pass. A deterministic C response
peer separately covers one-shot projection and remote-reference rejection.
RelWithDebInfo native CTest passes 181/181. The complete package gate passes on
macOS arm64 with Elixir 1.20.2 /
OTP 29.0.4: 285 passed (10 doctests, 4 properties, 271 tests), 11 optional
tests excluded and 95.0% coverage. Typed Browse handles, BrowseNext, explicit
release, page-to-page deadline/aggregate limits, subscriptions, cancellation,
complete policy/token interoperability remain unaccepted.

## Independent-peer native ByteString array round-trip, 2026-09-16

The independent Basic256Sha256 anonymous peer now exposes a writable
ByteString-array Value. Through the explicitly selected public `Open62541`
client, one typed Write sends two binary elements containing embedded zero and
non-UTF-8 bytes; a subsequent Value Read asserts the exact ordered base64
envelopes. All nine optional secure-peer tests pass. The Python peer is
test-only; this public client does not launch Python. This extends the partial
P02 typed service evidence but does not accept the full S01/S02, policy/token,
pagination or lifecycle matrices.

The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64
with Elixir 1.20.2 / OTP 29.0.4: 281 passed (10 doctests, 4 properties,
267 tests), ten optional tests excluded and 95.0% coverage. Native build,
documentation, audits and package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `test/interop/secure_peer.py` | `4c1155a51e48c68b710d568adb402bf1a3e692859fbe483d9b59e7f544466bd8` |
| `test/interop/native_secure_test.exs` | `c13b361574a5a6cbc1676e6015905ebe90dd2b2eb833503b596c56f88b8dafea` |

## Public native mutation preflight effect, 2026-09-16

The facade now preserves `effect: :none` for the explicitly selected native
client's finite local Write/Call input, handle, protocol and credential-shape
rejections. It continues to classify other mutation failures conservatively
as unknown, and it leaves the older generic client behavior unchanged. Focused
tests show invalid typed Write and Call inputs fail before the one-shot client
reads credentials or starts its C process; both errors retain no effect. This
is a partial WOP-X04 effect slice, not acceptance of transmitted timeout,
cancellation or full lifecycle cases.

The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64
with Elixir 1.20.2 / OTP 29.0.4: 281 passed (10 doctests, 4 properties,
267 tests), ten optional tests excluded and 95.0% coverage. Its native build,
documentation, audits and package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua.ex` | `d577861e8998a38252f03a303bef87f72ec106c4dc9528994efa80cce09cfe32` |
| `test/wotex/opcua/open62541_test.exs` | `e3a830aa67ca155e5451f382f75094395da0bf15153f252456fbd007204e53ff` |

## Explicit public native Session client slice, 2026-09-16

The explicitly selected `Wotex.OPCUA.Open62541` client now implements the
existing client port with caller-owned persistent and one-shot secure Sessions.
Persistent connect snapshots bounded credential files, verifies the executable
identities, activates the native Session and retains its temporary host until
explicit disconnect or owner loss. One-shot connect validates shape without
file or process I/O; each request snapshots credentials, opens a temporary
Session, performs one service operation and closes it. The client validates
concrete NodeIds and typed Variant inputs before dispatch, with no automatic
mutation retry. It currently returns the validated native DataValue, Write
status and Call result maps through the public facade. Browse, subscriptions,
complete one-shot compatibility projection, full lifecycle/cancellation and
the security policy/token matrix remain open. Selecting `Open62541` invokes no
Python runtime code.

Six default public-client tests pass. A C response peer injects deterministic
open/read/write/call/close frames to test owner, credit and cleanup wiring;
it does not establish OPC UA interoperability. Nine optional tests pass against
the independent Basic256Sha256 anonymous asyncua 2.0.1 peer. The public facade
there reads, writes/reads back/restores a Double and calls a typed Method in a
persistent Session; a one-shot read independently opens and closes another
secure Session. The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes
on macOS arm64 with Elixir 1.20.2 / OTP 29.0.4: 280 passed (10 doctests,
4 properties, 266 tests), ten optional tests excluded and 95.0% coverage.
Its native build, documentation, dependency audits and package/archive checks
pass. This is partial P02/S02/X04 evidence, not package acceptance.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/open62541.ex` | `fa9e0578462c801687a19c008b9eab1225454bc4fad4d1703d6903672d7c0382` |
| `lib/wotex/opcua.ex` | `6a322c21d190a2e236e08553f4305fa7910a1ed6426e120fdef77179fab7c5b4` |
| `lib/wotex/opcua/port_call.ex` | `fd5aac1a7814c22d11641dc6905bb190c54ebe0e2d5040eee4bb2030a3ea2312` |
| `test/wotex/opcua/open62541_test.exs` | `7ae6e55d997325055912a1b59f0413b2ca30d052a161199434203454ac89e2b8` |
| `test/interop/native_secure_test.exs` | `6729cff2cc49ee60e4a8123bee0ee12a09202744ad6ca205e36c1a75dc96e04d` |
| `test/native/host_probe.c` | `b6c799b743dc365e3462aac8c309164882b943519c78c3ad231c3737fc872ef9` |

## Native credential configuration projection, 2026-09-16

`Native.Config.new/1` now rejects unknown or duplicate option keys, malformed
native executable identities, insecure policy/mode shapes, invalid token forms,
non-absolute credential paths and out-of-range timeouts before file I/O.
`open_parameters/2` snapshots only named regular files under one monotonic
deadline, caps each at 64 KiB, rejects an excessive aggregate frame, and emits
the closed DER/bytes-envelope map for the existing C `open` request. The config
inspect form omits credential paths and binary passwords. Unit tests cover
anonymous, binary username and certificate token projection, the file and
aggregate limits, and invalid options. An eighth optional independent-peer
test opens and closes a real Basic256Sha256 anonymous Session using this
projection. The helper is preparatory: no public `Open62541` client or one-shot
projection existed at that source revision, the public adapter was Python-backed, and P02/P03 and
the full policy/token matrix remain open.

The focused configuration suite passes five default tests. Eight optional
secure-peer tests pass. The complete `WOTEX_PATH_DEPS=1 mix check --no-retry`
gate passes on macOS arm64 with Elixir 1.20.2 / OTP 29.0.4: 274 passed
(10 doctests, 4 properties, 260 tests), nine optional tests excluded and 95.1%
coverage. Documentation, audits, native build and package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/native/config.ex` | `83b7b168170e9afdc60b24ee46d9610dfcf86c2b4c9d9eb847b7363aacc63181` |
| `test/wotex/opcua/native/config_test.exs` | `ad7e3c3685fc00981ef1369949fdea6b2506cb996acd9486e4aa50cd6cc049bd` |
| `test/interop/native_secure_test.exs` | `aacb17ab1b8e8b85ba84adc48373a1d9a0198d4cf5c782728729f8fdb9806611` |

## Asynchronous native Method Call slice, 2026-09-16

The production C process now admits one Method Call after secure activation.
It translates concrete object and method NodeIds through the server NamespaceArray
and SDK-local namespace map, validates 0..64 typed input Variants, copies their
storage into SDK-owned memory and retains it until asynchronous completion or
client cleanup. The callback copies one bounded method result. The process and
BEAM owner validate the numeric method status, ordered input argument statuses
and typed outputs before spending and replenishing output credit. A Bad method
status or post-submission failure has unknown effect and is not retried. The
owner also preserves unknown effect after an unacknowledged Call timeout or
Port loss. NodeId-bearing inputs and outputs remain unsupported pending complete
namespace translation. This does not accept full P02/S02/X04, concurrent
operations, cancellation, subscriptions or the public native client at that
source revision; its default public adapter was Python-backed.

The focused Frame/Host suite passes 30 default tests, including the Call owner
timeout and 64-element result boundaries. Seven optional tests pass against the
independent Basic256Sha256 anonymous asyncua 2.0.1 peer: a real two-Double
Method Call returns ordered typed output, while a missing method preserves a
numeric Bad status and unknown effect. The independent peer is test-only Python.
The RelWithDebInfo native CTest suite passes 181/181. The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 269 passed (10 doctests, 4 properties, 255 tests),
eight optional tests excluded and 95.2% coverage. Its fresh native build,
documentation, dependency audits and package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/main.c` | `8c0295cdddc484b910dae91e91f0d582d62c4e7667dd7f7fd81c55c2a3aeb8b1` |
| `priv/native/session_open.c` | `e68603d04c7a2f4f23a7650f46daeb8b0a2830e94601f5a9fb544671d114c597` |
| `priv/native/session_open.h` | `3b103bef14f96a9ceb322508f4ab30d97846e6ff18276bd7e82c17e18b569866` |
| `lib/wotex/opcua/native/frame.ex` | `b5475fcd19c0cc06b031f813061e41f5d33a75c4db94d9ff68bd0d75ee810547` |
| `lib/wotex/opcua/native/host.ex` | `12c8c4236517aca7596e52b3339b21d458bec6c497a51389d0ebee9892defdc8` |
| `test/interop/native_secure_test.exs` | `f6b93a70ee2bc399ab051432dcd077b39bfecff36d30520c4da2607f79c772d2` |
| `test/interop/secure_peer.py` | `6b2eae7899b593afb98502dd478239579e7555634bdbe73ce9a82a70b5ee4174` |
| `test/wotex/opcua/native/frame_test.exs` | `a5ebadacdec692f80be570c463993f4d3ff367932d0051a70bd1c292b80fd62b` |
| `test/wotex/opcua/native/host_test.exs` | `16a36bbab3cd5818a9ebcd2cd21c9beeee5636c94ce95e81bae4e26a8fb8690b` |
| native CTest log | `dec6b9587d122962d837ced64444f9ad73a831773b2f5f2287a164e3cde7f5a2` |

## Asynchronous native Value Write slice, 2026-09-16

The production C process now admits one typed Value Write after secure
activation. It validates the closed node/index-range/Variant map, resolves the
input namespace URI to the SDK-local index, copies the Variant into SDK-owned
memory, and retains that copy until asynchronous completion or client cleanup.
One individual numeric Write status is returned. A Bad result or post-submission
timeout/connection failure reports unknown effect, and the BEAM owner also
classifies an unacknowledged Write after Port loss or local timeout as unknown.
There is no automatic replay or retry. NodeId-bearing Variant values remain
unsupported until namespace translation is complete. This partial slice does
not accept complete P02/S02/X04, concurrent operations, cancellation or the
public native client at that source revision; its default adapter was Python-backed.

The focused Frame/Host suite passes 29 default tests, including an unacknowledged
Write owner-timeout case. Six optional tests pass against the independent
Basic256Sha256 anonymous asyncua 2.0.1 peer: a typed Double Write is read back
and restored, and a rejected Write retains its numeric Bad status and unknown
effect. The RelWithDebInfo native CTest suite passes 181/181 cases.
The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64
with Elixir 1.20.2 / OTP 29.0.4: 268 passed (10 doctests, 4 properties,
254 tests), seven optional interoperability tests excluded and 95.2% coverage.
Its fresh native build, CTest, documentation, dependency audits and
package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/main.c` | `46fd01fb27c230dcd137641f4b721319e6c65ded38630077591a2a127300935d` |
| `priv/native/session_open.c` | `b9cad696a853719b5b3af737e2f40a66654c6518b9f18903c3eab05f41eb7ff2` |
| `priv/native/session_open.h` | `7fbf7e6e5d5aec4be78f26bd8610d8c26101d746e6e0b251d065d701616c623d` |
| `lib/wotex/opcua/native/frame.ex` | `49b0e24a10ea05026bb9b5703c44d8fe1a92b244e42cdecb3bcc9b673a1eb383` |
| `lib/wotex/opcua/native/host.ex` | `5131a51e2dae3300fea89c19f196b03cb90aa85cb2a0966faaa3ac779388e8ae` |
| `test/interop/native_secure_test.exs` | `6b3f03e5419912f7aee9a18265bb5e600b30f0392b8d260b59d95f4f91497fb4` |
| native CTest log | `a8e5b0e0935b302629ecda5a9e92c5897ba5d2e652dee83201ec9315fe097582` |

## Asynchronous native Value Read slice, 2026-09-16

The production C process now admits one concrete Value Read after secure
activation, with a null index range, one asynchronous SDK request and one
correlated IPC result. It resolves the public server namespace index through
its URI to the SDK-local index and checks the reverse mapping before issuing
the request. The existing native value codec emits the full bounded DataValue;
the BEAM frame decoder validates its typed shape before credit replenishment.
Bad attribute status returns finite `remote_error` with the numeric StatusCode.
NodeId-bearing result Variants remain explicitly unsupported until the inverse
namespace mapping exists. This does not accept P02/S02/X04 as a whole or bind
new X-F cases: cancellation, concurrent operations, output buffering, the other
services and the public native client remain open. The public default adapter
still requires Python.

The focused Frame/Host suite passes 27 default tests. Four optional tests pass
against one independent Basic256Sha256 anonymous asyncua 2.0.1 peer, including
the actual executable and BEAM owner reading a Double and a Bad read retaining
its StatusCode. The RelWithDebInfo native CTest suite passes 181/181 cases.
The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64
with Elixir 1.20.2 / OTP 29.0.4: 266 passed (10 doctests, 4 properties,
252 tests), five optional interoperability tests excluded and 95.2% coverage.
Its fresh native build, CTest, documentation, dependency audits and
package/archive checks pass.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/main.c` | `41b1713c8f63a14f95d2d9398c4a5f7e260e81eec2fb6335d41bce80c44eb279` |
| `priv/native/session_open.c` | `539e02450f036c6e60317c6390deabeafd1e9b45a7ba90cdac79e773d87524fc` |
| `priv/native/session_open.h` | `21040e48879919fa0cc66a72f7710908b31fa8bcb4fbef7ed2e0f7c9896912e6` |
| `lib/wotex/opcua/native/frame.ex` | `a35e3f80b55f9944f70fcf3d7e29c7554892c42735ceab507835bfe2aa80073d` |
| `test/interop/native_secure_test.exs` | `4446e122a981a070d83dbdca72fe795ad86fb25b54c4c6c5dfd37b2deb8cab76` |
| native CTest log | `5288b8a82cac815e4283b3ca61d6c554f50564bee13f73d03486f6b8bdee4fef` |

## Production secure open/close slice, 2026-09-16

The production `wotex_opcua_native` now runs the strict open-parameter and
credential gates, starts an asynchronous pinned SignAndEncrypt SDK Session,
reads the server NamespaceArray independently, rejects malformed/duplicate or
oversized namespace entries and an invalid/excessive revised timeout, then emits
one generation/ID-correlated success under the initial output credit. The
process retains the Session until explicit close or EOF. Close attempts an
asynchronous CloseSession with subscription deletion and bounded cooperative
teardown before its success response. The internal BEAM `Native.Host` decodes
only the closed open/close result shapes, maps the owner deadline and replenishes
validated response credit. `Native.Frame` rejects mismatched generation, ID,
timeout and namespace metadata.

The independent asyncua 2.0.1 peer passes three optional interop checks: the
C-only secure probe, the production executable's direct framed open/close, and
the BEAM owner through the separate custody guardian. The focused Frame/Host
unit suite passes 24 tests, including a default owner success/credit fixture;
the three optional peer checks passed separately. The RelWithDebInfo native
suite passes 181/181 CTest cases. The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 263 passed (10 doctests, 4 properties, 249 tests),
four optional interoperability tests excluded and 95.2% coverage. Its fresh
native build, CTest, documentation, dependency audits and package/archive
checks pass. This is one Basic256Sha256 anonymous peer lane;
it does not accept P02/P03, bind X-F17..F23, expose a public native client,
implement Read/Write/Call/Browse/subscriptions or remove the existing Python
runtime adapter.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/main.c` | `1b624910dd28bc07f359f21dff1a376fe6b8d07fb030bddc07a30839156b3f3b` |
| `priv/native/session_open.c` | `6cc1de2505fb77d6f0c2cb3ac7d2420a0a48b0fe8dc7af7d68e6f7d9b5702f67` |
| `priv/native/session_open.h` | `e121325623b89da1e569432d280e8913736c6e240e2d3b2ddeb91042b937f314` |
| `lib/wotex/opcua/native/frame.ex` | `500c7cc2dd5b2bf642843ffd58090c863bf712bbfd8cdcbca42a012b2ae7538e` |
| `lib/wotex/opcua/native/host.ex` | `e0d27f1441d66bb39a31cb9029101177b0a3c5f8ee483327f624012a9e252a4d` |
| native CTest log | `3f2627eb8e22f488279950b6de4f00403eb054de67552854548fb23b3f06f99d` |
| full gate log | `7992337aaaae807ae5f931cb08d56a90e6306904b8e51a197e845166315bb7b2` |

## Secure SDK configuration prerequisite, 2026-09-16

At that prerequisite stage, `open62541-secure-discovery-v2` extended the reviewed, exact-hash SDK patch:
when a caller supplies the pinned leaf and SignAndEncrypt policy, GetEndpoints
runs over that first secure channel. Endpoint URL and certificate substitution
and ambiguous matching user-token policies fail before CreateSession. The
existing revised Session timeout preservation remains. The source manifest
binds all pristine and patched file digests and the patch script. At this stage,
the production executable still rejected a valid `open` as `unsupported_protocol`.

`session_config.c` now configures the requested policy and explicit anonymous,
username or certificate token, installs the whole-DER pin/CRL/SAN/URI verifier
as the SDK callback, preserves a binary username password and forbids key
prompts or automatic reconnect. The C credential test passes 60 generated
cases and 145 assertions without network I/O. The uninstalled C Session probe
then connects to an independent asyncua 2.0.1 loopback peer using
Basic256Sha256 SignAndEncrypt, reads the actual server NamespaceArray (three
entries) and checks the server's positive, bounded 60000 ms revision. The
both optional ExUnit interop tests pass against that live peer. The RelWithDebInfo
native suite passes 181/181 CTest cases. The complete
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64 with
Elixir 1.20.2 / OTP 29.0.4: 261 passed (10 doctests, 4 properties, 247 tests),
two optional interoperability tests excluded and 95.8% coverage. Its fresh
native build, static SDK patch, CTest, documentation, dependency audits and
package/archive checks pass. These checks establish a prerequisite,
not the production owner, all policy/token combinations, services or P02/P03
acceptance. The normal runtime adapter still requires Python.

| Subject | SHA-256 |
| --- | --- |
| source manifest | `6cc2163a1ce9dca4c237a0b7a8da8af5f52c1869ae45b90464ab13e09e3523d1` |
| `priv/native/patch-sdk.cmake` | `df1acabefca781711a34b546e4a3ded85af95a46110cf9b0978685fd340fad2a` |
| `priv/native/session_config.c` | `4dcc0045f599a3b56e10de777a6fa5cecbaa624277bb0e35bbc508851257dce3` |
| `priv/native/session_config.h` | `35969525091fce3fd4ec0f19ba683ce804e92ea8286467392b1141e1a7205ee3` |
| `priv/native/session_probe.c` | `fc0fb3b41b718efe5340c313e1cf24b8e8b258e7acacc24cc7a5d0f0920449a5` |
| native CTest log | `54709fa7a0c742b1a0b4d15c543ced1ed9fa4e18f432110af77d4353241201c7` |

## SDK Session revision preservation, 2026-09-16

The pinned open62541 build now applies `open62541-session-revision-v1` before
SDK configuration. Its CMake script checks all three pristine file hashes and
all three transformed file hashes before writing anything. The source manifest
records those identities and the script digest. All modified files and the
patch log are receipt artifacts; tampering rejects build reuse. The required
build test independently extracts pristine upstream source, corrupts each of the
three inputs in turn, and checks that a rejected patch changes none of them.
It then checks the exact successful outputs and rejects reapplying the patch.

`native_sdk_session_revision` uses an actual SDK server bound only to loopback
and drives three asynchronous SDK client Sessions. It compares server-revised
`3210.5` ms against a 60000 ms request, equal 60000 ms limits, and a 1000 ms request
below the server maximum. It asserts the scalar and copied Double, rejects the
attribute before activation and after disconnect, and checks that the copied
value survives Session cleanup. This separate test binary uses Security None;
it proves SDK metadata preservation, not secure native owner acceptance. The
production executable still cannot open a Session. The adapter must still reject
invalid or excessive revisions before delivering an open result.

The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes on macOS arm64
with Elixir 1.20.2 / OTP 29.0.4: 261 checks (10 doctests, 4 properties, 247 tests),
one interoperability test excluded and 95.8% coverage. It includes a fresh
patched static SDK build, the patch corruption/reapplication/reuse assertions,
docs, dependency audits, package inspection and out-of-tree archive compilation.
The RelWithDebInfo native suite passes 181 CTest cases. A Debug
`WOTEX_SANITIZERS=ON` build passes all 170 cases selected by
`ctest --output-on-failure -R 'native_(security|sdk|ipc|json|value|contract)'`,
using `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`. The first-party driver/parser sources are
instrumented; the pinned static SDK/OpenSSL inputs are not. Linux security,
full native Session admission, secure peers and the Python-runtime replacement
remain required. No additional X-F case or P02/P03 acceptance is inferred.

| Subject | SHA-256 |
| --- | --- |
| source manifest | `4f9525afe5c6856e1421ad8524825163d27428bbc7e02b44bfca5674d53a0964` |
| `priv/native/patch-sdk.cmake` | `658028a4d97114cf98144bea0881bd0bbed4a174c29096e2f96b43d239e257cc` |
| `priv/native/sdk_revision_check.c` | `ce6658f299ab424d3fb2b0770d28771e819ac27c55c476a13384faf30d59e994` |
| `lib/wotex/opcua/native/recipe.ex` | `91c6d5821766abb21b84fc350d93bb3aa127a241cad6fe4947c49bf929d75c37` |
| `lib/wotex/opcua/native/build.ex` | `e83d653a2d053e5d6ed4062551946ca563960b1b1aea4cd1b7206988fe51ce37` |
| `test/wotex/opcua/native/build_test.exs` | `90b3073ce0928fe665a6958c8a61de5461c8516ae0f5b52e0bbd172a99187b2d` |
| native CTest log | `9a6351becd985aaa60bfbec793c4ae55affdcf2ae52c97ed5b5f2b0ce204cbb5` |
| native ASan/UBSan log | `279e0a6c141a72aa40905a63a756ce55a34e671a2ebef337ee2316de1ce5b11d` |

## Native credential preflight, 2026-09-16

The pre-network S03/X03 slice adds `priv/native/security.c` to the production
executable and hash-bound native build. `native_security_preflight` generates
ephemeral credentials in C, passes them through the strict JSON/open-parameter
boundary, and asserts 60 cases plus 36 peer-pin/time checks (96 assertions).
Inputs cover all three admitted policy names and token forms, DER/PKCS#8 and
container faults, key mismatch and weak keys, strong and weak signatures,
RSA-PSS certificate/CRL signatures, direct issuer versus intermediate trust,
DNS/IP/URI mismatch, wildcard/CN rejection, key usage/EKU, critical/duplicate
extensions, revocation and exact validity/update boundaries. Rejected input
must release every credential acquisition; repeated clear is safe. Unknown
noncritical certificate extensions remain admissible. This is preflight
evidence, not network policy or authentication interoperability.

On macOS arm64, the RelWithDebInfo native build passes all 180 CTest cases.
The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes with Elixir
1.20.2 / OTP 29.0.4: 260 checks (10 doctests, 4 properties, 246 tests), one
interoperability test excluded and 95.8% coverage. Its fresh pinned native
build, docs, dependency audits, package inspection and out-of-tree archive
compilation all pass.
The Debug `WOTEX_SANITIZERS=ON` build passes all 169 tests selected by
`ctest --output-on-failure -R 'native_(security|ipc|json|value|contract)'`, with
`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`. First-party sources/parser are instrumented;
the pinned static SDK/OpenSSL inputs are not. Clang static analysis of
`security.c` reports no diagnostics. These runs do not establish Linux security
or leak-detection acceptance.

The required Mix build test invokes the real executable with shape-valid but
invalid DER and asserts one `certificate_invalid` terminal, phase `opening`,
matching generation and no credential content. The native request's original
monotonic deadline is checked again after credential work. The C peer verifier
checks an exact whole-DER pin and current trust but is not yet installed as the
SDK callback. Valid preflight still ends with `unsupported_protocol`; P02/P03,
X-F30..F47 and replacement of the Python runtime remain unaccepted.

| Subject | SHA-256 |
| --- | --- |
| `priv/native/security.c` | `1e962e1580c5ee87991855980da471ad91a0ccfcc7019c9bb4f47086b96960f3` |
| `priv/native/security.h` | `34f636e010b145ba352424e3c1632c8226a3ed41ac5873a6c208228568644157` |
| `priv/native/security_check.c` | `8606ebf29e52aced99f467964e97d94b133983c7e0fb7de7f3c31ceb728a41e1` |
| `priv/native/main.c` | `2e217de4101f938642fb45e41e9aa5b9d5f2932d8a527a15bfe5114f2d804367` |
| `priv/native/CMakeLists.txt` | `6614c2559a74e2d2e713ccba4932ac42a2a0308fed7eea9a29bfc01437693588` |
| `test/wotex/opcua/native/build_test.exs` | `ecdbd8ca7ca78b64c518e1a520f2815368e3ccdedb69c331e6ffd0e16969479f` |
| native CTest log | `1750b3454a9f95a42d88381e87edc3a4b7c5b51b55b74d038e69db5e99a63081` |
| native ASan/UBSan log | `ed28a066c82f5d691f5eb9fe352e941e592ee1190597f54adf51f02173e10960` |

## WOP-P00 source, build and custody cohort

WOP-P00 passed on 2026-09-14 for the source/build/bootstrap and portable
process-custody boundary. `WOTEX_PATH_DEPS=1 mix check --no-retry` used Elixir
1.20.2 / OTP 29.0.4 on macOS 26.6.2 arm64. Coverage was the only ExUnit pass:
254 tests passed, one interoperability tag was excluded, and coverage was 96.3%.
The selected native build downloaded and verified the pinned source archives,
built static OpenSSL/open62541 and both first-party executables, then passed all
161 CTest cases. The native CTest output SHA-256 was
`e79c866df4d8debb3cdba9e8b9126b46f3ccba07cf2e987680b091c52da7442e`.

The build receipt bound these identities:

| Subject | SHA-256 |
| --- | --- |
| native source manifest | `909bb2cca1eeb20e755af093cc24b896ba94b578b81ee25d4924cfc406ae73b9` |
| open62541 1.5.7 source archive | `a4018b052c93fedb55f00558a85869b86f3bb2293184d322e33f2666c497eaeb` |
| OpenSSL 3.5.8 source archive | `59f86483992995df5a213df38d93f31eeafe3b34599309b3e088ba67ca0aad9c` |
| macOS arm64 `wotex_opcua_native` | `8c52d02d2ab66d95c36e9d5266ca8b5d15b24107837178f5656a2ebaeaeb3781` |
| macOS arm64 `wotex_opcua_custody` | `c3cd34e996542c79fbc9031e8067bb41bbe7415a5132e981c7a72db1296e5197` |
| custody fixture | `bd69b4c0bff4a43ae7318c95702d23e925ca93190c62bc88f52b508b4b306144` |
| runtime guardian source | `d08b553ed0cd4ba9b166e8b01aae8eddd96f97a8accc418632d68e3c75ad37d2` |
| independent custody driver | `ef8c45b3bea8727a8a9e6be0fe4985d8a798ff0d5bee1b870a6346f5ede498e5` |

WOP-G10 additionally passed in Linux arm64 and x86_64 containers resolved from
`debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171`.
Each architecture executed WOP-G01 through WOP-G09 once with strict
AddressSanitizer/UndefinedBehaviorSanitizer timing and once with LeakSanitizer:
18 executions per architecture, zero failures. The independent Linux driver
asserted exact byte/count/status projections, SDK reap within 500 ms, guardian
exit within the applicable allowance, and absence of leaked direct children.
`bin/check_native_custody.exs` makes those Linux sanitizer lanes part of the
default gate; macOS runs the portable corpus through the native build and CTest.

This evidence accepts P00 only. The native helper still exposes dependency and
bootstrap behavior, not a secure Session or application service. P01 and later
packets, complete native service framing, independent peers, the full platform
matrix and an archive-only native consumer remain required separately.

## WOP-P01 typed value and namespace cohort

The P01 gate uses Elixir 1.20.2 / OTP 29.0.4 on macOS arm64 with the locked
development dependencies. `WOTEX_PATH_DEPS=1 mix check --no-retry` passes 254
checks (10 doctests, 4 properties and 240 tests), with one interoperability test
excluded and 96.3% coverage. The required fresh native build passes 178 CTest
cases, including every WOP-X-F01 through WOP-X-F16 projection and WOP-NF17
namespace fault case. Build receipts bind the native contract fixture separately
from the first-party source files and upstream archives.

A separate Debug build enables `WOTEX_SANITIZERS=ON` and runs
`ctest --output-on-failure -R 'native_(value|contract|json)'` with
`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`. All 167 selected tests pass on macOS arm64.
The same 167 cases also pass on Linux x86_64 with leak detection enabled,
using the pinned Debian image recorded for P00, GCC 12.2.0 and CMake 3.25.1.
Both builds instrument the first-party native sources and parser with
AddressSanitizer/UndefinedBehaviorSanitizer; their static SDK and OpenSSL inputs
retain the pinned versions recorded for P00 and are not sanitizer-instrumented.

An isolated Elixir 1.18.4 / OTP 27.3.4.15 run passes the default suite:
10 doctests, 4 properties and 241 tests, zero failures and two exclusions
(`interop` and `native_build`). That run does not repeat the SDK build.

| P01 input | SHA-256 |
| --- | --- |
| native contract corpus | `b1505300b4bcb5d0fd596c67a6e027bcbef123b386c8f379f0bd0ecf5e995ec1` |
| typed value corpus | `b38f6fc3b8ea23fd55a2c899146bb643376b6e4ace9af3b71d1221615b0db1ec` |
| native contract runner | `748535edab646afbe7847f5e4af8d42c824fa05c72850ebea0033918465ac0f9` |
| value codec implementation | `ef7a4b16e6485fec0f903e2f55aedadf3a982fa0c662ec0bb07cb5a781ba7593` |
| value codec header | `1aeef02790f45be1071ec6a0063cb40d70b8e4e49880b60b876052187e658b16` |
| direct SDK fault runner | `433783382e1b74dc6560440e5af2f14359af07c754819dd41f128b875c362c4f` |

P01 accepts pure typed values, identity/reference preservation, SDK value
projection and exact namespace translation. The namespace arrays are explicit
inputs to a pure primitive. Their acquisition and lifetime, native Sessions,
services, subscriptions and independent peers remain required by later packets.

## Initial WOP-P02 input boundary (package remains open)

On 2026-09-16, the actual `wotex_opcua_native` process used `ipc.c` and the
strict production JSON reader to assemble and validate an outer request line.
`native_ipc_admission` exercises every split of its valid line, two coalesced
lines, the exact frame ceiling, NUL rejection, closed keys, duplicate keys,
exact integer endpoints and malformed envelope fields. The required native
build test speaks to the installed executable through a real Port and asserts
ready followed by exactly one terminal for split valid input, expired deadline,
fractional timeout and duplicate ID. No SDK service request is sent.

`WOTEX_PATH_DEPS=1 mix check --no-retry` passed 254 checks (10 doctests, four
properties, 240 tests), one excluded interoperability test and 96.3% BEAM
coverage. Its selected native build rebuilt the pinned sources, ran CTest and
checked receipt tampering. A separate CMake build against the already verified
pinned static prefixes passed 179/179 CTest cases. A Debug
`WOTEX_SANITIZERS=ON` build with `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`
and `UBSAN_OPTIONS=halt_on_error=1` passed 168/168 selected
`native_(ipc|json|value|contract)` cases on macOS arm64. These local runs do
not establish Linux sanitizer coverage for the new slice.

| P02 input source/evidence | SHA-256 |
| --- | --- |
| `priv/native/ipc.c` | `39a10286f82841f74b323f98c5d225ccb1f5d6297d5b85538f19a8a27aa2be1f` |
| `priv/native/ipc.h` | `cd603dc0ad185f52cd23210e89107bebb2420dad40d4fb26faac22926e035e3a` |
| `priv/native/main.c` | `c388e31dbcee974bb032a9221aca73c76f5aecd1eaca9eceeab41e9461baabeb` |
| `priv/native/ipc_check.c` | `731617b3cc25db22036d557e54633e5eb99477b4592d940e58d908f26b61f55c` |
| `test/wotex/opcua/native/build_test.exs` | `a2a4d40235b7f6e5ea858634bba5baa8a59658f41deff14fcb94da9e7dbfefcb` |
| local normal CTest log | `30b15182ed0c19767c2ee50327aca1d67256c449413beef94db8ee47af4f8ebe` |
| local sanitizer CTest log | `dd8819b7bc7f05582a58c8fb804739d531bd009e44399d003f857d24e8a49932` |

This is a process-input and terminal-rejection slice, not acceptance of P02.
Per-operation parameter validation, persistent Session activation, namespace
acquisition, credits, responses, cancellation and all X-F17..F23/X-F49..F57
remained required at that source revision. Its Python adapter then owned public
network operations; that adapter has since been removed.

## P02 owner-side frame and clock projection

The next direct `main` slice adds `Native.Frame.admission/5` and `request/6`.
It maps the ready-native and separately captured owner-receive clocks to one
native deadline, rejects expiry and conversion overflow, caps the native timeout
to the remaining owner budget, and encodes a closed JSON request line with
checked integer, ID, operation, depth, node, string and total-byte limits.
The pure test covers exact boundary values and malformed inputs. The selected
native build test now uses this production encoder to send its split request to
the pinned executable; no native response or service success is claimed.

| Owner-side source/test | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/native/frame.ex` | `3be493df22a1d3601eda876e61d657ee0d134592287f7e8ca431f84484eead5a` |
| `test/wotex/opcua/native/frame_test.exs` | `4f277be341a886e01ee718b3eaf661da7a13114a4d71016071009161e1f03080` |
| `test/wotex/opcua/native/build_test.exs` | `5ffef075e9e4e402d7e6202d4a1f262a0389f857c7cd636f18a8fa5a3aef2564` |

The full `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes 257 checks
(10 doctests, four properties, 243 tests), one interoperability exclusion and
96.3% BEAM coverage with a fresh pinned native build and CTest. P02 remains
open: its owner has no response relay, credits, activated Session or services.

## P02 terminal-only owner exchange

The subsequent internal `Native.Host.request/4` path allocates a BEAM-owned
uint64 generation, accepts only its original owner, sends the validated frame
through the independently owned runtime guardian, and waits under the original
deadline for one bounded terminal. `Native.Frame.terminal/2` accepts only the
matching generation, closed terminal/error fields, finite code/phase/effect
tables and optional uint32 status; malformed and extra output closes custody.
The real pinned-build test asserts `unsupported_protocol` from the actual C
process through `Native.Host`, while the pure decoder checks replay, duplicate,
unknown, truncated and oversized controls. A foreign caller cannot send a
request. A separate stalled native fault peer proves that a pending request
expires and custody reaps the process without an extra owner notification. The
host releases the process after its terminal and does not admit a
success-shaped service response.

| Terminal owner source/test | SHA-256 |
| --- | --- |
| `lib/wotex/opcua/native/host.ex` | `04239b127b8c3939970fed217c1473c5a5a554b0630ad91eb9b387aadda6542e` |
| `lib/wotex/opcua/native/frame.ex` | `8058886abdef268433398e01c9a38748cd4f7b731305f4b69a722cfd5cc9110f` |
| `test/native/host_probe.c` | `a0c57fad8f3f5c75a98522977aed5e5121859759b1717371db72758798b1e3c9` |
| `test/wotex/opcua/native/host_test.exs` | `5e29db0b9a658c0e71eb91e6d69b2c324526297d3c9eaaf6433167b5ffd1c457` |
| `test/wotex/opcua/native/frame_test.exs` | `934234510742072dbc8af099015164ffe8bd2511eaf5e5b93d1ee76b2df563cc` |
| `test/wotex/opcua/native/build_test.exs` | `f8caab61924723ce86d380630efa85f6d4b8743f63372ddc1ae89e78989beb08` |

The complete `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passed 259 checks
(10 doctests, four properties, 245 tests), one interoperability exclusion,
95.9% BEAM coverage, this real exchange and the fresh 179-case native CTest
build. P02 remains open: no persistent
Session, normal response relay, credits, services or independent native peer
interoperability is accepted.

## P02 native open shape rejection

The next C ingress slice validates the closed `open` parameter map before any
SDK network call. It recognizes exactly the three specified policy URIs and
`SignAndEncrypt`, bounds endpoint/ApplicationUri strings and session timeout,
checks all five certificate/key/trust/CRL fields as canonical base64 envelopes,
and checks anonymous, username or certificate user-token shapes. The C runner
tests all three allowed policy literals, downgrade/unknown fields, noncanonical
base64, token forms and timeout boundaries. The required native build test sends
a shape-valid and a downgraded `open` through the production BEAM encoder to
the actual executable. The former terminates `unsupported_protocol`; the
latter terminates `invalid_request`. The tiny test byte envelopes are not
certificates and no cryptographic or Session success is inferred.

| Open-shape source/evidence | SHA-256 |
| --- | --- |
| `priv/native/ipc.c` | `ba85da703e92b6291216d725cf228bec8dd1562bab7ad7cf031dc2713800bd0a` |
| `priv/native/ipc.h` | `a6aaccc565dfdf08d5301b5b89b77e772fd4144b3d53e05d13fd0a1869df9280` |
| `priv/native/ipc_check.c` | `8411cdc3610a137c54e79ce2672d63a2f7f6efb5fe55c00e771b5420d18a96f7` |
| `priv/native/main.c` | `af1f9df48859b97a71cf4b855fb8e133e739df6619e0f60991f0c073bfcc2cea` |
| `test/wotex/opcua/native/build_test.exs` | `f15b549e11d6b15741b84b497ac8370c4cc274812cd7930264e22d8358b812a1` |
| local normal CTest log | `e5e1d81009b01d4eb41d985c374c8d0f53754a22a58c47e3f14b1f3e2ae0eb88` |
| local sanitizer CTest log | `9f1a83e592e3d68bfcabf0f09ca7cc6540a86fc6563161b3a00715be9aa51745` |

The local static-prefix build passes 179/179 CTest cases; the macOS arm64
ASan/UBSan selected lane passes 168/168. The full
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passed 259 checks (10 doctests,
four properties, 245 tests), one interoperability exclusion and 95.9% BEAM
coverage, including the fresh pinned build, docs and archive. P02 remains open,
and server identity,
certificate chain, CRL, private key and token security must be validated before
any native Session attempt.

## P02 initial credit and generation admission

The BEAM owner now emits the version-1 initial credit control with sequence one,
16 messages and 262144 bytes before its first request. Native ingress checks the
closed credit map and exact integer bounds, binds the first valid generation,
then rejects requests without the credit, mismatched generations and further
grants before output is consumed. It does not yet emit a normal response or
replenish consumed credits. The C driver exercises exact uint64 generation,
positive quantity ceilings, fractional/extra/duplicate fields and invalid
event kinds. The selected native build test sends the production credit and
request to the real C process and separately proves missing-credit rejection.

| Initial-credit source/evidence | SHA-256 |
| --- | --- |
| `priv/native/ipc.c` | `30287e937c00c2efac518128700d7ec8d67c2bd45f772275da5c5f8fcef90129` |
| `priv/native/ipc.h` | `cb4f64c492ff8fa8559ba6325d403e77a28ff489bd96912db22c9303ba50b5d6` |
| `priv/native/ipc_check.c` | `a7cf8af8dd73a642ac6f498f1e46c12f11d8e3c516370b264ab8cf9001f4a275` |
| `priv/native/main.c` | `9fb005cff6c2f7f75130a43db4fc0f2adc080e929adead5c46c8e9a7ea51821e` |
| `lib/wotex/opcua/native/frame.ex` | `a670f5dec7261e586e505228e8e6bb00ac154296914bcff456b148edacc9bb9b` |
| `lib/wotex/opcua/native/host.ex` | `5473b070b452a00b0af3ead77778641fa9fbfed926e29b86d0b8e4c31719cc74` |
| `test/wotex/opcua/native/frame_test.exs` | `d7d6907c311a1514aeec00a8b2e9157a199e93dd5345a29e7a72c0f5f421922e` |
| `test/wotex/opcua/native/build_test.exs` | `865ec93810607588238f5c81b4b18936017c1a8057dd6f614aa977cb8033b315` |
| local normal CTest log | `25735c8461c630f6ec668e10c8d76643d452bed92eb2e15e7ebf80d61b0c1d0d` |
| local sanitizer CTest log | `667665b1a6152c9691b077d0438f0b3ceac79c2788bedbc801ae1a6384d97f01` |

The local static-prefix build passes 179/179 CTest cases; the selected macOS
ASan/UBSan lane passes 168/168. `WOTEX_PATH_DEPS=1 mix check --no-retry` passed
260 checks (10 doctests, four properties, 246 tests), one interoperability
exclusion and 95.8% BEAM coverage, including the fresh pinned build, package
checks, docs and out-of-tree archive. P02 is still open: normal
credit consumption/replenishment, output queues and every service remain absent.

## Historical Python-adapter interoperability

Real secure asyncua 2.0.1 peer: PASS for read, write/readback/restore, browse,
unknown-node failure, expired certificate, wrong host/URI, untrusted CA and
revoked certificate. Both sides use asyncua; this is a real wire/security proof,
not independent-stack interoperability or OPC Foundation certification.
Intermediate trust chains are outside the implemented security profile.

The first-party Python adapter and its interop test have since been removed.
The independent peer remains in `test/interop/secure_peer.py`, with its pinned
test-only dependencies in `test/interop/requirements.txt`. The fixture generates
disposable credentials outside the repository. The Elixir gate does not install
Python dependencies; audit the optional peer environment separately with
`pip-audit --disable-pip --no-deps -r test/interop/requirements.txt`.

Interoperability tags are excluded by default. Explicit invocation requires the
configured peer and must fail if that peer or expected response is missing.

## Evidence identities

The native build tests under `test/wotex/opcua/native/` cover source admission,
workspace ownership, guarded commands, static build, dependency self-test and
receipt validation. Each completed build records separate source, build-code,
tool, option and artifact hashes in `wotex-native-build.json`; its command logs
are also hash-bound. The executable's one-tick SDK check is a dependency test,
not complete DataValue metadata or wire interoperability evidence.

The native secure Session, credit protocol, end-to-end 100 ns metadata and
independent asyncua/native workflow remain required implementation. Software
build/run entry points remain specified work. The historical adapter result
above does not attest the current native source tree.

The hashes identify reviewed test sources, not an immutable release or a promise
that all future test executions will pass. The mandatory gate and optional peer
commands above must be rerun after relevant changes.

| Test source | SHA-256 |
| --- | --- |
| `test/wotex/opcua/binary_test.exs` | `a173b9a4687c7965e4b45eab7809b066a428c0de26fe254f230e2fb7a8f23a9b` |
| `test/wotex/opcua/contract_test.exs` | `e9d677fe79d5d8b4fdb88d1d597b0d6bb3cb2bdbe2889a9cc4003432cb5e5f33` |
| `test/wotex/opcua/dependency_security_test.exs` | `3c45b778a241b2a577f9481c6a7ec08f4f8ec747f72a6d5e7deaf3265510e072` |
| `test/wotex/opcua/mapping_test.exs` | `2768c115820bcd56364bde5d2101bc13dc242fc92f5ca0a2c1b62b01e7812f93` |
| `test/wotex/opcua/port_test.exs` | `bf7dfcf70fa9afc680f07d4b861c56ecf954b01e8d280b12d7981849cc19cb48` |
| `test/wotex/opcua/value_test.exs` | `5c173dfdd5a27d60887064fe64041a3d5fd2434442bcd8abe431e00345f96089` |

## Native runtime custody

`test/wotex/opcua/native/custody_test.exs` executes the checked-in
`custody-contract-v1.json` cases using `priv/native/custody_check.c`. CTest repeats
those nine native cases during each actual SDK build. Assertions cover exact
fragmented bytes, simultaneous traffic, owner EOF with full pipes, stopped SDKs,
receiver loss, contained stderr, complete final output, blocked final drains,
group isolation and one shared cleanup deadline. The Linux test driver audits
orphan adoption independently of the guardian. A separate LeakSanitizer lane
retains the 500 ms SDK reap bound and explicitly reports instrumentation-only
post-main exit time; ordinary and ASan/UBSan timing lanes retain the 500 ms total
guardian bound. The [runtime custody contract](../../priv/native/runtime-guardian.md)
defines those separate acceptance conditions. These checks do not implement or
accept SDK frame credits, secure Sessions or OPC UA subscription ownership.

## BEAM native bootstrap

`native/ready_test.exs` executes every exact frame in `native-ready-v1.json`.
`native/executable_test.exs` exercises bounded file admission and SHA-256 identity.
`native/host_test.exs` compiles the real custody guardian with a separate C fault
peer, then asserts malformed readiness, fragmented output, failed executable
admission, stopped SDKs, owner death during hashing and readiness, post-startup
loss, and a suspended claimant's original deadline. A temporary Supervisor child
does not restart a failed host. Each started fault peer records both native
process identities and the tests check their absence after cleanup; the separate
C custody driver verifies direct-child reaping.

The required native build test starts the installed SDK helper and guardian
through `Native.Host` using their receipt digests. This is a real process-ready
integration check without an OPC UA endpoint or service. It does not accept a
secure Session, application data, subscription credit flow or remote cleanup.

## Native JSON syntax and numbers

`native/json_test.exs` compiles the reviewed parser and first-party adapter, then
executes every case in `native-json-v1.json` through the bounded command guardian.
The driver receives only the input frame and allocator size, and returns parsed
node counts, exact integer projections and IEEE-754 bit patterns. The tests
compare the complete declared output. Long frame boundaries use an exact prefix,
space count and suffix instead of repeated literal whitespace in the fixture.
The CTest self-test separately exercises strict flags and basic pool ownership.
Vendor tests reject missing, altered and symbolic source/license files. These
checks do not accept typed SDK construction, response serialization or services.

## Pure identity and reference structures

`standalone_contract_test.exs` executes WOP-F01 through F13 from
`contract-v1.json` through public `Binary` functions. The fixture input alone
reaches each decoder; the complete actual projection is compared with the
declared expectation. Test tags contain the fixture case, requirement IDs and
SHA-256 of the corpus bytes. `binary/names_test.exs` and
`binary/reference_test.exs` exercise exact masks and field order, all NodeId
kinds and NodeClasses, nullable/empty text, maximum string and URI lengths,
numeric overflow, every truncated field, invalid masks, and arbitrary byte
streams. Unconsumed tails remain byte-exact, including a tail larger than the
consumed identity limit. `typed_values_test.exs` exercises every supported
Variant type, null/empty arrays, dimensions, future numeric type preservation,
opaque binary/XML bodies, mixed-endian GUIDs and exact adjacent timestamp ticks.
DataValue assertions cover metadata masks, Bad/Uncertain status, present null
versus absent data, clamped/orphan fractions and the complete 1 MiB byte budget.
These checks cover the pure value and identity/reference structures of N02;
they do not accept SDK construction or Browse services.

## Native typed value conversion

`priv/native/fixtures/value-v1.json` contains 133 concrete JSON inputs and exact
Part 6 binary results or typed rejection results. The required native build
executes each case separately through `value_check` against pinned open62541
1.5.7. The constructor retains exact signed and unsigned integers, DateTime
100 ns ticks, explicit array shapes and encoded ExtensionObject identities.
The checker clears and overwrites the parser storage before SDK encoding, then
clears the SDK arena before serializing the projected result. Rejected inputs
must leave no result and restore the arena checkpoint.

`value_fault_check` adds 17 direct SDK structure cases. They cover invalid
parameters, unknown types, dimensions, finite floating values, UTF-8, namespace
conflicts, DataValue flags, allocation exhaustion and size boundaries. Maximum
1024-element arrays, 65536-byte strings and byte bodies, and an exactly 1 MiB
encoded Variant succeed. The corresponding excessive values fail. An input
constructor cannot mask these direct SDK faults by rejecting them first.

The source-bound native build receipt includes the corpus, both test drivers,
typed library sources and CTest log. The [value codec contract](../../priv/native/value-codec.md)
defines its arenas and result lifetimes. This evidence accepts conversion
primitives only. SDK network-decoder allocation checks, received reserved type
IDs, complete framed service output, native Session ownership and independent
peer metadata workflows remain separate required implementation.
