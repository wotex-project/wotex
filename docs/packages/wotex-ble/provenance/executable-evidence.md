# Executable evidence

Current implementation: typed domain APIs, persistent native host ownership,
native SDK components, verified guardian-owned native startup, Agent/procedure/
stream behavior and Runtime integration. The current source has a passing full
local gate: 9 doctests, 17 properties and 269 tests, 58 declared interoperability,
hardware and software-stress exclusions; 95.9% coverage.
The [virtual-controller fixture](virtual-controller.md) and its
[software run receipt](software-run-v4.json) execute the 11 public BLE and
Runtime interoperability tests, including scenarios ported from the retired
Python adapter lane, and the 5 WBL-C09 lifecycle stress tests against the
Mix-built C++ host, real BlueZ 5.85 and two virtual controllers in both BEAM
lanes. The independent fixture provider is compiled C++17 over GDBus/GIO. The
x86_64 guest lane remains required. The Python persistent
adapter, its packaged helper and its unit tests are removed.

Open finding: with a Runtime relay `max_queue_length` of 1, the buffered initial
report can be rejected as `receiver_overflow` when the opening result is still
in the Runtime owner mailbox. The full default suite reproduced this under load;
60 isolated repetitions did not. The WBL-I05 overflow case therefore uses a
bound of 2 and still injects three reports while the owner is suspended. This
establishment race is recorded, not accepted as fixed.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check --no-retry` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See the [security posture](../security.md) and the dependency-security test.

## Acceptance boundary

[WBL.07](../specs/WBL.07-native-backend.md) defines the required native binary,
Mix/ExUnit tasks, exact version lanes and credit/resource tests. The executed
component, startup and BEAM credit cases are identified below; unlisted native
build and software-flow requirements remain open. A passing current gate,
a listed test path or a source hash cannot establish execution of that target.
Each completed software run must
bind case, corpus, source, SDK/binary, toolchain and cleanup-result hashes.
The mandatory runtime matrix is Elixir 1.18.4/OTP 27.3.4.15 and Elixir
1.20.2/OTP 29.0.4. Only identified executed lanes count as passing evidence.

## Committed source identities

These hashes identify the committed implementation/test inputs reviewed here;
they are not release artifacts or a claim about every future run. Fixture WIP is
excluded. Native software results require their own immutable manifest.

| Source | SHA-256 |
| --- | --- |
| `test/wotex/ble/contract_fixture_test.exs` | `3c4612f65da02f4df819691f0710798dcdf6ec41bf2efb51ba1f944cc8e9c548` |
| `test/wotex/ble/runtime_integration_test.exs` | `ae2937ab1d0ecc8059036aded75201113737268bab73eeea1ad7a09903977b4c` |
| `test/wotex/ble/dbus_bridge_test.exs` | `fb2eb03cc7238c3bcb249266216e33cbe86030bce9eaed3d1e30a802281ea933` |
| `test/wotex/ble/stream_bridge_test.exs` | `f65ce06b4b2e04eaed00c89760bcb4379781e6342da52172615cf9315094e009` |

## P01 peer identity and value codecs, 2026-09-20

`test/wotex/ble/identity_value_test.exs` and
`test/wotex/ble/contract_fixture_test.exs` execute the pure P01 boundary through
the public APIs. The focused command passed 36/36, including nine properties:

```console
mix pkg wotex-ble test test/wotex/ble/identity_value_test.exs \
  test/wotex/ble/contract_fixture_test.exs
```

WBL-F01..F05, F09 and F10 compare their exact `contract-v1.json`
expectations. The remaining assertions cover explicit public/random peer
identity, object-path syntax, handle and generation edges, forged structs, all
integer widths and both byte orders, finite float widths and signed zero,
non-finite encodings, strict Boolean bytes, UTF-8, opaque bytes, invalid options
and the 512/513-byte boundary. This is pure identity and conversion evidence;
it does not establish ObjectManager association, duplicate live target
resolution or a GATT exchange.

| P01 subject | SHA-256 |
| --- | --- |
| `lib/wotex/ble/peer.ex` | `d43e24e4b09fa1fbf4ce834c9aad505fc833114e5f03659cb853e71455c48d9a` |
| `lib/wotex/ble/address.ex` | `a3df36cdfb68f444aaa1b191525166aaf780fd17aeffc00c0c6189fddfd2dbb3` |
| `lib/wotex/ble/value.ex` | `f6b263a96a2585b58c179dfe64dd29b4e2f8fa2c661dd30404ea2c688d58e118` |
| `lib/wotex/ble/uuid.ex` | `5e34bac9523130101c6195954e622b369528a916492fd79c6ab014fc8efc3ce3` |
| `test/wotex/ble/identity_value_test.exs` | `33aa72000b5bdaa2857befe9c99c963f0ea93eba9f90fab92d801d0642b39674` |
| `test/wotex/ble/contract_fixture_test.exs` | `3c4612f65da02f4df819691f0710798dcdf6ec41bf2efb51ba1f944cc8e9c548` |
| `priv/fixtures/contract-v1.json` | `9de800b0910e7b92386f2e1a86d095f313224ad42c3b81a30a81975dccf00848` |

## P02 persistent discovery ownership, 2026-09-20

The focused bridge and page command passed 37/37:

```console
mix pkg wotex-ble test test/wotex/ble/dbus_bridge_test.exs \
  test/wotex/ble/native_pages_test.exs
```

The public bridge case opens the persistent owner, returns two typed pages for
duplicate UUID instances, rejects an unknown cursor and an excessive page limit,
and closes idempotently. Its lifecycle cases cover absolute deadlines, the
64-request admission bound, dead queued callers, owner death during blocked I/O,
joined close callers and forced bridge termination. The native page fixture
adds 1,024-characteristic ordering, frame/node limits, generation invalidation,
foreign and evicted tokens, token reuse and 2,000 successive generations.

The private-D-Bus component evidence below covers listener-before-snapshot
reconciliation, typed Device1/GattService1/GattCharacteristic1 association,
pinned sender identity, ServicesResolved loss and owned/borrowed link cleanup.
The [current software receipt](software-run-v4.json) pins the same production
and test source hashes and records three consecutive 16/16 runs in each BEAM
lane. Its public WBL-V03/V04 cases discover and disambiguate the virtual GATT
peer and verify that an owned link connects and drains through its own cleanup.
These claims do not accept pairing, read/write procedures, notification sessions
or Runtime mapping.

| P02 subject | SHA-256 |
| --- | --- |
| `lib/wotex/ble.ex` | `07b146de76f75d6b62e03764bb6219c7ddd6b88b3e56a5050cf16b51d96a973d` |
| `lib/wotex/ble/bluez.ex` | `4378eafb7232888c005e0889a43e71b303512fd66f588bd33bd8bbd3ae0f0bc4` |
| `lib/wotex/ble/bluez/connection.ex` | `6ed870e311f2cb64d717edf4079fce23f206f09938e37473bb3c77a1f74983ac` |
| `priv/bluez/native/discovery.hpp` | `39a42994d7d4ef51a1e1dc21641edc4c7d8e412459dc5ac1893fc6a2351edbdd` |
| `priv/bluez/native/objects.hpp` | `541721c352433895f36e52ccd3569ff86edf13e0f40e0854d1d5008b2720ed1f` |
| `priv/bluez/native/pages.hpp` | `6d1660aa8dcf45febc8026fc23967c66dc0bfc525b58e54760f7220526f8e357` |
| `test/wotex/ble/dbus_bridge_test.exs` | `fb2eb03cc7238c3bcb249266216e33cbe86030bce9eaed3d1e30a802281ea933` |
| `test/wotex/ble/native_pages_test.exs` | `8057b1edfecfa706302c60fac773e41af20ad950dfc7daaea3890c78328e14e8` |
| `test/native/discovery_test.hpp` | `66b32ab87a057de280564290c6e7f555f24c77c3fb8d19490a3da0ed2ed01fc0` |
| `test/native/objects_test.hpp` | `68daa87095347dea3a0080cbe59882abd6ea2a767894dd972821ebce19b6dc99` |
| `test/native/pages_test.cpp` | `506f0ad73421b3e288246ab47cfe15b7ecede3b8e617ecb7d312c5ec6051ad0a` |
| `test/native/host_process_test.hpp` | `06fab2032562d82630253f209d9d4ee05559a609dfb68b8de740202ca88eb716` |

## P03 explicit pairing Agent decisions, 2026-09-20

The focused public pairing boundary passed 34/34, including one property:

```console
mix pkg wotex-ble test test/wotex/ble/pairing_value_test.exs \
  test/wotex/ble/dbus_bridge_test.exs
```

The tests cover all prompt kinds, normalized service UUIDs, redacted challenge
inspection, prompt and decision bounds, incompatible answers, exact peer and
deadline binding, explicit callback policy, policy crashes and timeout, owner
death and invalid native results. Successful, rejected, PIN and passkey bridge
flows each use the first-party persistent owner; policy configuration and
challenge values do not enter its recorded frames or process status.

WBL-B-F19..F24 execute native prompt/decision projections and WBL-B-F25/F26
execute accepted and rejected RegisterAgent/Pair/UnregisterAgent lifecycles on
the private D-Bus fixture. The [current software receipt](software-run-v4.json)
pins the same sources and runs the public virtual-controller Pair case in both
BEAM lanes. That case checks accept, reject, policy timeout and a forged
challenge ID, followed by remote Agent and sender cleanup without CancelPairing,
RemoveDevice or RequestDefaultAgent. This evidence does not accept read/write,
notification or Runtime behavior.

| P03 subject | SHA-256 |
| --- | --- |
| `lib/wotex/ble.ex` | `07b146de76f75d6b62e03764bb6219c7ddd6b88b3e56a5050cf16b51d96a973d` |
| `lib/wotex/ble/agent.ex` | `df2713ee5482379516081983557b0d0f43d38c5a1a8c97f2ce8bcf4b5d217cfa` |
| `lib/wotex/ble/challenge.ex` | `6d8eb36aa5a317feca4655a4584cfd69ebd6b395509c40e7c0da72d0b6b849b4` |
| `lib/wotex/ble/bluez/pairing.ex` | `9be9c2620932e5a6854850a73f17f80f585c59c1e45e1a0f47a4d9a08aae0218` |
| `lib/wotex/ble/bluez/connection.ex` | `6ed870e311f2cb64d717edf4079fce23f206f09938e37473bb3c77a1f74983ac` |
| `priv/bluez/native/agent.hpp` | `90a475851d917b456fa42f845367afb77466090cc6c3d4c27238a8419abedaa0` |
| `priv/bluez/native/pairing.hpp` | `b6dcc3efc4c1597a01c1d0ad5ecfb31c79d3d32af62cb9dbc313b7f5aec565b1` |
| `test/wotex/ble/pairing_value_test.exs` | `b840355f331479bdaf7578754debb2e1b58dc014b13e7cb3c06b84b3ea1dfca3` |
| `test/wotex/ble/dbus_bridge_test.exs` | `fb2eb03cc7238c3bcb249266216e33cbe86030bce9eaed3d1e30a802281ea933` |
| `test/native/agent_test.hpp` | `4e5abfa401da3a967d738434ceb2c5f92448d24d604b20f6dddc6a77d1d5c10c` |
| `test/native/pairing_test.hpp` | `bec5654ff917574545516591cb4be8dcbb4d70cdba0a3188f8800bfaa6adeb67` |
| `test/interop/bluez_test.exs` | `c1c2fdb401a583680cc06e375f6b8461449ae570f9935c0e501ecd8bbccdd835` |

## P04 acknowledged GATT procedures, 2026-09-20

The focused procedure, schema and bridge command passed 37/37, including two
properties:

```console
mix pkg wotex-ble test test/wotex/ble/procedure_test.exs \
  test/wotex/ble/bluez_schema_test.exs \
  test/wotex/ble/dbus_bridge_test.exs
```

The public cases validate codec options before admission, canonical byte
envelopes, read/write result shapes, bounded D-Bus error names and incompatible
custom-client returns. Persistent bridge cases cover 0- and 512-byte values,
command-only and missing flags, forged target selectors, every admitted BlueZ
error name, queued expiry, active timeout, process loss, missing/duplicate/wrong
submission events and malformed acknowledgements. Each submitted write is
counted once; no case retries it or falls back to a command write.

WBL-B-F27..F32 execute the native typed procedure projections on the private
D-Bus fixture. The [current software receipt](software-run-v4.json) pins the
same sources and runs the public WBL-V05 case in both BEAM lanes against the
virtual GATT peer: raw and uint16 reads, one acknowledged write, independent
readback, duplicate-UUID disambiguation, stale/address-mismatch rejection and
typed NotPermitted failures. This evidence does not accept notification or
Runtime behavior.

| P04 subject | SHA-256 |
| --- | --- |
| `lib/wotex/ble.ex` | `07b146de76f75d6b62e03764bb6219c7ddd6b88b3e56a5050cf16b51d96a973d` |
| `lib/wotex/ble/address.ex` | `a3df36cdfb68f444aaa1b191525166aaf780fd17aeffc00c0c6189fddfd2dbb3` |
| `lib/wotex/ble/value.ex` | `f6b263a96a2585b58c179dfe64dd29b4e2f8fa2c661dd30404ea2c688d58e118` |
| `lib/wotex/ble/bluez.ex` | `4378eafb7232888c005e0889a43e71b303512fd66f588bd33bd8bbd3ae0f0bc4` |
| `lib/wotex/ble/bluez/connection.ex` | `6ed870e311f2cb64d717edf4079fce23f206f09938e37473bb3c77a1f74983ac` |
| `lib/wotex/ble/bluez/response.ex` | `4742e720c51e744188d0b02b75f98b86be01a4d0ce26bfe6b1ee5884588c12a5` |
| `priv/bluez/native/procedures.hpp` | `dffa557693a4572a9f2a5bbfdfdf5734b1e1208a87fbdf026fa521513202caf7` |
| `test/wotex/ble/procedure_test.exs` | `76e7c4b3d4461c73d34d23aa6c6b18ff1fbcdb8f29b1fd6544a8578006b31815` |
| `test/wotex/ble/bluez_schema_test.exs` | `168e50faafe7d9a2e53d717f04bb6d41d5a6c2b2d6d7ef6919f87b3bbacc7258` |
| `test/wotex/ble/dbus_bridge_test.exs` | `fb2eb03cc7238c3bcb249266216e33cbe86030bce9eaed3d1e30a802281ea933` |
| `test/native/procedures_test.hpp` | `0b9e37351e57e33061ceb40505742217321302e5377483d26254b89d56a1ed13` |
| `test/interop/bluez_test.exs` | `c1c2fdb401a583680cc06e375f6b8461449ae570f9935c0e501ecd8bbccdd835` |

## P05 notification and indication ownership, 2026-09-20

The focused stream value, owner, credit and characteristic command passed
34/34, including two properties:

```console
mix pkg wotex-ble test test/wotex/ble/stream_value_test.exs \
  test/wotex/ble/stream_bridge_test.exs \
  test/wotex/ble/report_flow_test.exs \
  test/wotex/ble/characteristic_test.exs
```

The public cases cover mode selection, the both-flags limitation, finite receiver
and codec options, forged handles, owner death, overflow, early establishment
failure, wrong report identity, terminal conversion errors, concurrent and
uncertain cancellation, 64 active subscriptions and 1,000 completed lifetimes.
The report ledger acknowledges only the contiguous admitted prefix, applies
frame and byte credit, retires one stream without a tombstone and cannot mint
credit from malformed controls.

WBL-B-F33..F41 execute native mode, value and StartNotify/StopNotify projections
on the private D-Bus fixture. The [current software receipt](software-run-v4.json)
pins the same sources and runs WBL-V07..V09 against the virtual GATT peer in
both BEAM lanes. The public cases deliver repeated equal notification and
confirmed indication values, preserve `:bluez_value_change` source metadata,
release a receiver-dead CCC session and keep a second sender and link alive when
the first closes. This evidence does not accept Runtime mapping.

| P05 subject | SHA-256 |
| --- | --- |
| `lib/wotex/ble.ex` | `07b146de76f75d6b62e03764bb6219c7ddd6b88b3e56a5050cf16b51d96a973d` |
| `lib/wotex/ble/subscription.ex` | `f44070945089bc5d78979185a14ec7ae6f4b56d1b9fc963a53374b159b0bfd28` |
| `lib/wotex/ble/characteristic.ex` | `099f8b0f62aca179e6e1216628246656af0a547a3890674eeaa9d628a7f1146c` |
| `lib/wotex/ble/bluez.ex` | `4378eafb7232888c005e0889a43e71b303512fd66f588bd33bd8bbd3ae0f0bc4` |
| `lib/wotex/ble/bluez/connection.ex` | `6ed870e311f2cb64d717edf4079fce23f206f09938e37473bb3c77a1f74983ac` |
| `lib/wotex/ble/bluez/subscription_owner.ex` | `3eb04f41484886699faf1c2e670c4eb78f1e66e6e27f1ef7936e42dc0b6e4214` |
| `lib/wotex/ble/bluez/report_flow.ex` | `fce321b02e3b4caa2931a54247350c6b7c599ab25c123ded1e9ea7db93396498` |
| `priv/bluez/native/notify_value.hpp` | `f94e4c4e5f16d0215cc069503a2ead3bd395138dd2f391dd15fd1983d1ddcf5d` |
| `priv/bluez/native/notifications.hpp` | `3666029cfdc72c27ae9c6bf03452b699b7702abc2c6148db58c99c9ec585568e` |
| `test/wotex/ble/stream_value_test.exs` | `6ec6a1c012c35b7e83920ea2d3d5416e584ce309c4f4a5c1d992905909b8694c` |
| `test/wotex/ble/stream_bridge_test.exs` | `f65ce06b4b2e04eaed00c89760bcb4379781e6342da52172615cf9315094e009` |
| `test/wotex/ble/report_flow_test.exs` | `d92f38bcd5425e1aa4ae1514f406d656f177612ea63c7da201769aaadec040ed` |
| `test/wotex/ble/characteristic_test.exs` | `620cffa79c215f6a66abe64c0a86666d705b5206bfba07cb4df2acb358aff40f` |
| `test/native/notify_value_test.hpp` | `b5c0d2eb1d1cc62f4522d92c0fce3f86746c04e2b86e4fe1c41cd470630b1767` |
| `test/native/notifications_test.hpp` | `846e3af19c20a7ad9037b729e2cd7220f8b70040df4b950cce5db439d0e2bf99` |
| `test/interop/bluez_test.exs` | `c1c2fdb401a583680cc06e375f6b8461449ae570f9935c0e501ecd8bbccdd835` |

## P06 Runtime mapping and live health, 2026-09-20

The focused mapping, health, bridge and Runtime command passed 56/56:

```console
mix pkg wotex-ble test test/wotex/ble/mapping_test.exs \
  test/wotex/ble/health_test.exs \
  test/wotex/ble/dbus_bridge_test.exs \
  test/wotex/ble/runtime_stream_test.exs \
  test/wotex/ble/runtime_integration_test.exs
```

The cases cover typed Form addresses, exact target selection, known selector
applicability, finite media/security/profile choices, every value codec, native
read/write result identity and Property/Event stream conversion. Runtime stream
cases cover no invented initial value, repeated equal reports, changed stop
routes, forged handles, connection loss, 64 opening reports, receiver overflow,
owner death, a single absolute deadline and stalled native cleanup. Health cases
admit only the fixed persistent response and reject fabricated or malformed state.

WBL-B-F49..F55 execute the live Device1 query on the private D-Bus fixture. The
[current software receipt](software-run-v4.json) pins the same sources and runs
five public Runtime interoperability cases in each BEAM lane against the virtual
GATT peer. Those cases cover typed read/write, unsupported pre-acquisition cells,
Property/Event delivery, receiver-death cleanup and cancellation through the
original route. This P06 claim is limited to S05; WBL.06's complete corpus and
consumer classification remain separate.

| P06 subject | SHA-256 |
| --- | --- |
| `lib/wotex/ble.ex` | `07b146de76f75d6b62e03764bb6219c7ddd6b88b3e56a5050cf16b51d96a973d` |
| `lib/wotex/ble/mapping.ex` | `f9f6b0d63adc30862eb1bf269f76883715f58e8e7afedc52522cbe37cae50211` |
| `lib/wotex/ble/transport.ex` | `613a00667a4c8fa74812cff6cf42d346ccb1e20edcdcdd3e74df148d48f4051f` |
| `lib/wotex/ble/runtime_relay.ex` | `97e3feea00c0b237143c7af92c7bfa793cf5b3e9957040b5a37b12d09daa380b` |
| `lib/wotex/ble/bluez.ex` | `4378eafb7232888c005e0889a43e71b303512fd66f588bd33bd8bbd3ae0f0bc4` |
| `lib/wotex/ble/bluez/connection.ex` | `6ed870e311f2cb64d717edf4079fce23f206f09938e37473bb3c77a1f74983ac` |
| `test/wotex/ble/mapping_test.exs` | `7e69552cf6ffef94efdf58e598febe83f3eb32ddac0ea155952c65e635a2c58a` |
| `test/wotex/ble/health_test.exs` | `9469d739662696fa744f31a5e281150d126531ed4889d85fb872e9f7be49cbff` |
| `test/wotex/ble/dbus_bridge_test.exs` | `fb2eb03cc7238c3bcb249266216e33cbe86030bce9eaed3d1e30a802281ea933` |
| `test/wotex/ble/runtime_stream_test.exs` | `16d2043f3f5f3aa7d20b20a75ac2713af07e2faf292a2c5963824061841ae4eb` |
| `test/wotex/ble/runtime_integration_test.exs` | `ae2937ab1d0ecc8059036aded75201113737268bab73eeea1ad7a09903977b4c` |
| `test/native/health_test.hpp` | `33c8524f5e9b393c1e2e591036bd9dee3ee124636e5c06847f641938bd8b6162` |
| `test/interop/bluez_runtime_test.exs` | `038f9906d97e3bc8fd478af86e9a4ae9a7dba92b54de53f6d9d8cb3c3c39e906` |

## P07 virtual-controller GATT workflow, 2026-09-20

The local fixture-contract command passed 10/10:

```console
mix pkg wotex-ble test test/wotex/ble/software_fixture_test.exs
```

It checks the native fixture stack, source and asset admission, immutable build
verification, both run lanes, exact guest/peer/ExUnit evidence and rejection of
failed, panicked or incompletely cleaned lanes. A receipt-wide read-only audit
compared all 237 recorded input hashes with their committed `HEAD` blobs; every
identity matches. The heavier software lane was not rerun for this packet.

The [current software receipt](software-run-v4.json) has SHA-256
`1c72be53be73c66eab7a1c94de4156a42c927a1d17546199a93e63d3bc53b111`.
It binds manifest `5268db6e1757624949b364cd0fd5f7934a3de83a54e9db1932e76fa6f22df463`,
the ARM64 native host
`26fc5ac60345c1780da7150d403ebee7be56cc93d2bea92c3c4fbdf66ebe9685`,
BlueZ 5.85 and three owned images. Three consecutive runs pass 16/16 tests in
each supported BEAM lane. All six lane results report zero remaining containers,
native senders, Agents and notification sessions.

The public workflow discovers and disambiguates the independent virtual GATT
peer, reads `3412`, writes `7856` through acknowledged WriteValue and reads it
back. It exercises denied operations, stale and mismatched targets, explicit
pairing decisions, repeated notifications, confirmed indications, receiver
death, independent sender preservation and owned-link cleanup. The two virtual
controllers, private bluetoothd/D-Bus and compiled C++ GDBus/GIO provider contain
no physical radio or Python client adapter. This accepts the Linux ARM64 P07
workflow; it makes no RF or x86_64 claim.

| P07 subject | SHA-256 |
| --- | --- |
| `lib/wotex/ble/software/build.ex` | `289f0e1e623b7ddeb3c3ba2c17f4b7b73137eb9b08022f8e6c45ea8b12dcfe62` |
| `lib/wotex/ble/software/fixture.ex` | `6fb5746867f8e76f08d03ed27259f88a5956aa08d9d5480095773868bf8feacc` |
| `lib/wotex/ble/software/run.ex` | `4e5fec396d5e878a0cd43964345004b6127bcce9ab80776cfbf802b48aa4dd59` |
| `test/wotex/ble/software_fixture_test.exs` | `830e9fb0311250755caf8d8d257a098375bb4fc07a679100b1cb25c1342c13aa` |
| `test/interop/virtual/public_peer.cpp` | `7112b0bf8374b4ef2feacde1fe2a8d0db9a7613fc4ed694484b4999a7cdc97c3` |
| `test/interop/virtual/public.sh` | `b306658e5b22edca45396edb0419ff6b8985fb2471b1af6297e2583fc80a241f` |
| `test/interop/virtual/build_manifest.exs` | `e280bd2d0cc3f4775e3b1b22aecb2d32a0d34634e046fbd9e52fa3218a51cd60` |
| `test/interop/virtual/Dockerfile.system` | `58849ac7b37c1e60f0ac1b64e950621af6e476ccd436ef10670ac42d4c0f50c7` |
| `test/interop/virtual/Dockerfile.bluez` | `4d5543d992c4928b7e85c1f325c0aa52711a58d0da4c37177624ab42c27530e5` |
| `test/interop/virtual/Dockerfile.public` | `1e760777ffbf52c09a33ecb0e5eaa10896f3310d26e98c32a5b7550f05f53f99` |

## Native C++ request parsing

`test/wotex/ble/native_frame_test.exs` compiles the shared production
`priv/bluez/native/frame.hpp` parser and executes B-F01 through B-F05 with exact
corpus inputs. `test/native/frame_test.cpp` also exercises uint64/int64 limits,
overflow, duplicate/escaped keys, malformed UTF-8 and surrogate pairs, depth/node/
collection/line bounds, every split point, coalesced frames, truncated EOF and
100000 monotonic request IDs. The pinned nlohmann header hash is an assertion.

The focused ExUnit lane and Linux ARM64 GCC ASan/UBSan executable pass. This is
native parser evidence, not D-Bus ownership, complete .13 flow control or GATT
interoperability. The required Linux x86_64 reference lane remains separate.
Production selection requires the complete verified SDK/guardian cohort described
below; selection alone does not establish the remaining native flow obligations.

## Native build workspace

`test/wotex/ble/native_build_test.exs` and `native_source_test.exs` execute the
WBL-B01 build contract in the default suite. Deterministic build operations
drive the production recipe, workspace lock, manifest and audit code: exact
arguments, tool and platform admission before mutation, manifest identity and
read-only reuse, forged or changed manifests, retained failure locks and logs,
architecture mismatch, failed or expired steps, missing libraries, Python and
absolute-runpath dependencies, wrong sonames and malformed ready probes. The
source tests admit the packaged libdbus pin, reject links and foreign archive
roots, and transfer from a local verified-TLS server with trust, status, digest,
size and deadline failures. The packaged command guardian is compiled and run
for output, deadline and argument bounds, including a guardian that ignores
them.

The [native build receipt](native-build-v1.json) records two actual Linux runs
of `mix wotex.native.build` from a Debian 12, Elixir 1.18.4 / OTP 27.3.4.15 image
defined by `test/native/Dockerfile`: native arm64 and x86_64 under Docker Desktop
emulation. Each downloads and verifies libdbus 1.16.2, builds the shared library,
fixture daemon, host and guardian with GCC 12.2.0, CMake 3.25.1 and Ninja 1.11.1,
and verifies reuse on a second invocation. The actual host emits the exact
ready frame with closed input on both lanes. These runs establish artifact and
startup identity only; advisory scanning, sanitizer builds, the software tasks,
the complete native corpus and BlueZ/GATT execution remain open.

## Native corpus ownership and built host process

`test/wotex/ble/native_contract_test.exs` checks the native corpus format, case
identifiers, exact expectation shape and known operations. Every case listed in
`executed_cases` must belong to an owner test that selects its operation or
identifier and compares `expectation.value`; every other owned case fails the
check. All 67 cases are recorded as executed. The per-case status fields that
disagreed with `executed_cases` were removed, so the top-level list is the
single execution record.

`test/interop/native_host_test.exs` admits the host and runtime guardian of a
completed Mix native build workspace through their manifest digests and the
production `Artifacts.verify/2` path. It launches the pair with the production
guardian arguments. B-F06 captures the exact ready frame, closes the Port and
observes zero surviving guardian or host processes within 1000 ms. The same
flow initialization and open request is written unsplit and split at every
byte; each split yields the unsplit reply
(`transport_unavailable` for an absent private bus), exit status 1 and zero
survivors. Malformed JSON, a 131,073-byte unterminated line, duplicate flow
initialization, a request before open and duplicate JSON keys each close the
generation with status 1 and no reply; a truncated frame followed by owner loss
releases both processes. The host writes no stderr, so noisy-stderr containment
remains covered only by the WBL-G custody corpus.

On Linux arm64, from the `test/native/Dockerfile` lane image and a fresh
workspace built from the current sources, `native_host_test.exs` and
`native_bus_test.exs` pass 38 tests with `WOTEX_BLE_DBUS_SOURCE` and
`WOTEX_BLE_DBUS_BUILD` set to that workspace's libdbus source and build
directories. The bus lane includes B-F19 through B-F41, B-F49 through B-F55 and
B-F61 through B-F63. On the emulated x86_64 lane, a fresh workspace passes the
three `native_host_test.exs` tests. Its `native_bus_test.exs` setup exceeded the
fixture's 15-second compiler deadline under emulation, so those 35 tests were
invalid there and are not recorded as x86_64 results. These are process and
private-bus component results, not sanitizer, BEAM process-flow or BlueZ/GATT
evidence.

## Native report flow across suspended BEAM owners

`test/wotex/ble/native_process_flow_test.exs` executes B-F11 through B-F13 in
the default suite. It compiles the production runtime guardian and
`test/native/flow_source.cpp`, admits both through the public native selector
digests and opens an ordinary `Wotex.BLE.connect/1` and `subscribe/2` session.
The test-only source answers open and subscribe itself and opens no D-Bus
sender. Every later value callback enters the production `NativeReports`,
`Credits`, `ReportQueue` and `NativeOutput` code, one callback per event-loop
iteration, exactly as native notifications do. The test suspends the actual
connection, stream owner or final receiver, creates the source's start marker
so production begins at callback zero, resumes at 50 ms and samples until
1050 ms.

Samples count report lines waiting in the connection mailbox and report
messages waiting in the stream owner mailbox, with their encoded bytes and
queued receiver values. The corpus projection requires at most 64 reports,
1 MiB of report bytes and the control reservation throughout, one terminal
error, no delivery after it and zero surviving connection, owner, guardian or
source processes within 1000 ms of `disconnect/1`. The test further requires
the session to remain ready with no retained subscription. A suspended
connection or stream owner receives exactly the 16-report stream window before
native `queue_overflow`. With only the receiver suspended, credit still returns;
macOS runs end at its 64-value bound with `receiver_overflow`, while a Linux run
ended after 20 values with native `queue_overflow` because callbacks outpaced
credit return. Both are bounded single-stream terminations and are accepted. Before the error vocabulary fix in
`Response`, the native `queue_overflow` terminal was an invalid response and
closed the whole connection.

The three cases pass repeatedly on macOS arm64 and on the Linux arm64 lane. The
callback source replaces BlueZ and D-Bus; SDK notification delivery and
sanitizer execution remain separate evidence.

## Native sanitizer lanes

`WOTEX_BLE_NATIVE_LANE` selects the WBL-G10 lane for every component executable
that ExUnit compiles in the frame, credit, byte, output, page, report, custody,
guardian-startup, command and private-bus tests, including the SDK host process
compiled by the bus fixture. The sanitizer lane compiles them with ASan/UBSan and
no recovery and disables exit-time leak scanning for strict timing; the
leak-audit lane enables LeakSanitizer and the custody driver's named
`--leak-audit` allowance. Harness waits scale; library deadlines and custody
assertions do not. The [sanitizer receipt](native-sanitizer-v1.json) records
all three lanes on Linux arm64 with GCC 12.2.0: 96 tests pass in each. The
leak-audit lane runs the 1,000-launch guardian startup case with 32 launches.
Running the default guardian startup and command tests on Linux exposed cleared
PATH values that stopped GCC from finding `ld`; compilation now keeps PATH.
The BEAM-launched startup and process-flow executables and x86_64 sanitizer
lanes remain unaccepted.

## Mix software fixture and virtual-controller lanes

`test/wotex/ble/software_fixture_test.exs` executes the software build and run
task contracts with deterministic Docker operations: exact arguments, tool
admission before mutation, fixture input hashing with modes and link rejection,
pinned download failures, failed image builds with retained lock and log,
foreign image platforms, malformed guest evidence, sources changed during a
build, read-only reuse with image and artifact verification, and run rejection
of failed guests, kernel panics, unreleased peers, incomplete ExUnit counts and
remaining containers. The Mix tasks report fixed usage and failure messages.

The [software run receipt](software-run-v1.json) records an actual build on
macOS arm64 with Docker Desktop and three consecutive runs of that verified
build. Each run boots one QEMU guest per BEAM lane and passes all 10 public
tests in `bluez_test.exs` and `bluez_runtime_test.exs` against the Mix-built
native host, with clean peer release, zero guest processes and controllers and
zero remaining owned containers. These are BlueZ-to-BlueZ virtual-controller
results with an independent GATT application, not an independent protocol
stack or physical RF. The first runs exposed the two native close and input
defects recorded above.

`test/software/lifecycle_stress_test.exs` is tagged `:software`, excluded from
the default suite and run by the same guest after the public files. The
[first stress receipt](software-run-v2.json) records a fresh verified build and
three consecutive runs, 15 of 15 tests in both lanes, with per-lane
`stress.jsonl` samples. The [Python-peer receipt](software-run-v3.json) repeats
that with the ported owned-link, address-mismatch and wrong-challenge scenarios.
The [current receipt](software-run-v4.json) binds the compiled C++17 GDBus/GIO
peer and passes 16 of 16 tests in both lanes across three consecutive runs. The
WBL-C09 counts, baselines, forced faults and memory observations are
described in [virtual-controller.md](virtual-controller.md). An earlier attempt
failed once in the lower lane because the open/close cycle checked
`Process.alive?/1` immediately after `disconnect/1` returned, before the
connection process had exited; the cycle now waits for its `DOWN` message within
the cleanup grace. The fault cases use a fixture-owned delayed ReadValue, an
injected truncated frame, SIGKILL of the host and a peer-side disconnect; they
are not physical link-loss measurements.

## Native report reservations

`test/wotex/ble/native_credit_test.exs` binds B-F07 through B-F10, B-F14 and
B-F15 to the production `credit.hpp` manager and `report_queue.hpp` deferred
queue. Exact byte/sequence acknowledgements release only the consumed prefix;
retirement preserves outstanding credits until acknowledged and cannot release a
different stream's reservations. A transmit attempt without credit enters the
same bounded queue that `NativeReports` uses; B-F10's seventeenth attempt stays
queued after the sixteen-report stream window. Native tests exercise 64 active
streams, 64 outstanding frames, the 1 MiB byte ceiling, forged acknowledgements,
a false retirement barrier, 100000 subscription lifetimes with no retained
closed-stream records and the queue's per-stream, 64-entry, 1 MiB, ordering and
discard bounds. The seven focused ExUnit tests pass. A Debian 12 Linux ARM64
lane with GCC 12.2.0 (`g++-12 12.2.0-14+deb12u1`), ASan/UBSan and leak
detection compares all six flow traces with the corpus and runs the credit and
report invariants. These traces use explicit byte lengths and component calls;
they are not process-flow or SDK callback evidence.

`test/wotex/ble/report_flow_test.exs` exercises the production BEAM
`ReportFlow` ledger and `SubscriptionOwner` admission boundary. Two live stream
owners complete out of order without acknowledging a gap; a retirement barrier
consumes only its stream, a later live-stream completion advances the exact
contiguous prefix, and duplicate/post-retirement frames cannot resurrect the
stream. Receiver overflow sends no internal acknowledgement. The ledger asserts
the 64-frame, 1 MiB, per-stream window, uint64 and exact generation boundaries.

`test/wotex/ble/native_startup_test.exs` compiles
`test/native/beam_startup_sdk.c`, verifies its identity, and launches it through
the packaged guardian. The real Port exchange sends the exact native
`queue_limit`, accepts two sequenced value reports, and requires acknowledgements
whose cumulative byte counts include each encoded newline. It then emits the
retirement barrier before cancellation success. Separate cases inject wrong
generation, unknown stream, malformed terminal and false retirement controls;
the exact connection generation closes. A valid terminal control retires only
that stream and preserves the session.

This is actual guardian/Port/BEAM credit-flow evidence against a deterministic
C process boundary. It does not execute the C++ SDK against BlueZ, sustained
callback stress, the required sanitizer matrix or public Runtime virtual-peer
acceptance.

## Native private D-Bus ownership

`test/interop/native_bus_test.exs` compiles `test/native/bus_test.cpp` against
libdbus 1.16.2. The production `bus.hpp` component owns a private connection,
asynchronous Hello registration, watches, timers and at most 64 pending calls.
It rejects reused message serials, invalid reply signatures and success after
the absolute deadline. Closing cancels pending calls and releases only that
connection; a second sender retains its bus identity and remains usable.
Closing from a reply callback is an asserted lifecycle case.

The selected macOS fixture and Linux ARM64 and x86_64 GCC ASan/UBSan component
executables pass against private daemons. The
ExUnit test command
guardian owns the daemon's process group and bounds command time/output/cleanup.
The fixture does not open the host system or session bus. Exact libdbus source
identity is specified in WBL.07; the selected fixture requires explicit source
and build directories and rejects a runtime library version mismatch.

The same fixture exercises source/path/signature-checked signal listeners,
removal inside callbacks, a 64-listener limit and 100000 listener lifetimes with
no retained records. `service.hpp` installs its ownership listener before the
asynchronous match/owner lookup. The fixture owns `org.bluez` on the private
daemon, asserts the distinct client/service unique names, then releases and
reacquires that name from a separate sender. The original service tracker
terminates once, cancels pending work and closes its private connection without
adopting the replacement. Cancelled establishment and late Hello also clean up.

The service-name fixture is an identity/ownership test, not a BlueZ GATT peer.
This evidence does not establish GATT, Agent1 procedures, the complete native
Port helper or the planned SDK build task.

## Native typed discovery snapshots

`test/native/objects_test.hpp` constructs actual libdbus typed ObjectManager
messages and exercises the production `objects.hpp` decoder through the explicit
native fixture. Assertions cover exact peer/device/service associations,
UUID normalization, optional uint16 handles, generation precision and bounded
unknown flags. Wrong variant types, duplicate dictionary keys, FD-bearing
messages and malformed peer values fail. A real one-descriptor signal on the
private daemon produces no callback and releases its descriptor on connection
close; a second connection remains usable. The over-capacity two-descriptor
fault runs in an owned native child that exits and is reaped within 1000 ms.
The parent retains no descriptors after that child fixture completes. On macOS,
the observed ancillary-data truncation leaves a descriptor after connection
close alone; process teardown supplies the required cleanup. Linux ARM64's
connection-close path also passes the two-descriptor fault. Neither result
substitutes for the final BEAM/native-host lifecycle fixture.
Native peer and snapshot constructors
restrict discovery to validated values.

The fixture exercises 4096 objects, 64 interfaces, 256 properties, 65536 aggregate
dictionary entries, 4096-byte paths and 1024 selected services/characteristics
at their boundaries. Unknown variant payloads are skipped without copying them
into the owned snapshot. These are typed native decoding tests; the separate
live ObjectManager fixture below exercises acquisition and reconciliation.

The native decoder also accepts exact typed metadata change/removal signals.
Its signal vectors exercise changed booleans, unknown-property omission,
invalidated properties, added objects and removed interfaces. Wrong signatures,
wrong variants, duplicate names, changed/invalidated overlap and the 256/64-entry
boundaries are asserted. This validates decoding; notification delivery is a
separate procedure.

## Native live ObjectManager discovery

`test/native/discovery_test.hpp` serves typed ObjectManager replies and metadata
signals through an actual private D-Bus daemon. It exercises `discovery.hpp`:
listeners precede the first snapshot, a signal before a stale reply forces a
fresh query, and four continuously raced replies fail `snapshot_unstable`.
Only the pinned BlueZ unique sender can change state. A directly addressed
forged signal from another sender is ignored; Value-only and unknown-property
changes do not invalidate discovery.

The fixture checks stable generations, changes restored before refresh, changes
visible only in a new snapshot, identity retargeting rejection, selected service
removal with no characteristics, malformed variants, loss of ServicesResolved
and owner replacement. A pending query admits no second refresh. Its deadline
returns `timeout`; close and late replies leave zero pending calls, listeners,
watches and timers. A callback can close its own discovery owner.

This peer implements the D-Bus boundary without a Bluetooth controller. These
tests do not establish radio discovery, real BlueZ Connect/Pair/ReadValue/WriteValue,
GATT notifications, the complete Port helper or the virtual-controller profile.
The public Elixir connection now launches only the native host through its
guardian; see the scripted protocol lane and virtual-controller receipts.

The native connection cases issue actual D-Bus Connect and Disconnect methods to
the private fixture service. Both owned and borrowed modes preserve an initially
connected link without either method. Borrowed disconnected/unresolved devices
fail. Owned startup waits for an actual ServicesResolved signal and a fresh typed
snapshot after Connect acknowledgement. Lost or malformed Connect acknowledgements
retain the attempt's cleanup responsibility; a typed rejection acquires no link.
The fixture asserts the identical unique sender for Connect and Disconnect,
suppression of late replies, and cancellation of pending calls. A blocked
Disconnect reply releases local resources within the cooperative allowance.
This is native D-Bus procedure/ownership evidence. BlueZ/controller execution
and full guardian/SDK integration remain separate acceptance requirements.

## Native canonical byte envelopes

`test/wotex/ble/native_bytes_test.exs` builds the production `bytes.hpp` codec
under the bounded native command guardian. WBL-B-F16 through WBL-B-F18 bind
exact corpus inputs to native results. RFC 4648 section 10 known answers and
an independent BEAM Base codec comparison establish the expected byte order
and encoding. Native checks cover every length from zero through 512, all octet
values, 513-byte rejection, zero-length views, invalid schema fields, embedded
NULs, non-alphabet text, missing padding and every nonzero pad-bit value.
The codec enforces decoded length before allocating output storage. It has no
SDK or process side effects. ReadValue, WriteValue and stream delivery through
the complete native backend remain separate procedure acceptance requirements.

## Native process custody

`test/wotex/ble/native_custody_test.exs` compiles the packaged runtime `custody.c`
and the standalone pipe-level `test/native/custody_check.c` fault driver under
the tooling command guardian. WBL-G01 through WBL-G09 bind the exact custody
corpus to observed byte counts, resource reaping and timing. The shared runtime
source is SHA-256
`d08b553ed0cd4ba9b166e8b01aae8eddd96f97a8accc418632d68e3c75ad37d2`.

Cases cover malformed startup, unintended inherited descriptors above a lowered
descriptor limit, fragmented and simultaneous bidirectional streams, full pipes,
stopped helpers, receiver loss, contained stderr, complete final output, ordinary
background group cleanup, isolation and one unchanged cleanup deadline. The
consumer is a native pipe reader independent of Erlang's Port driver. Its blocked
reads establish kernel backpressure; they do not establish a suspended BEAM
mailbox bound. The guardian implementation has no SDK or GATT behavior. Admission
of both executable digests, actual host integration and report-credit acceptance
remain separate requirements.

## Native Agent method boundary

The actual libdbus fixture in `test/interop/native_bus_test.exs` executes
`exported_methods` in `test/native/bus_test.cpp`. It checks exact unique sender,
object path and interface routing, bounded PIN/passkey returns, fixed rejection
without diagnostic text, deferred same-serial replies and no-reply suppression.
Malformed registrations and duplicate routes fail. One hundred thousand export
lifetimes retain no closed records; 64 concurrent exports exhaust admission.
A callback can remove its own export or close its bus connection.

The fault driver stops its own independent D-Bus daemon to apply kernel
backpressure. The producer reaches the explicit two-response queue bound and
fails closed; close releases queued responses and export records. The driver
resumes only its owned daemon. This is method dispatch and allocation evidence,
not acceptance of RegisterAgent, Device1.Pair, policy challenge forwarding or
bond/connection cleanup through the complete native helper.

## Native pairing prompt values

`test/native/agent_test.hpp` exercises the production `agent.hpp` boundary for
all seven Agent prompt kinds, exact peer association, PIN/passkey limits,
display progress, UUID normalization and explicit compatible decisions. It
checks original request retention after the caller releases its reference,
one-answer ownership, exact reply serial/destination, wrong kinds, forged
options, unknown members and fixed rejection without diagnostic text.

WBL-B-F19 through WBL-B-F24 execute concrete prompt/decision inputs through
`test/interop/native_bus_test.exs`. The native driver receives input only;
ExUnit compares the independently encoded reply projection with the corpus.
The pure cases construct actual typed libdbus messages and perform no bus or
pairing operation. The P03 evidence above supplies the separate registration,
policy deadline, late-reply and Pair/UnregisterAgent lifecycle coverage.

## Native Pair and Agent lifecycle

`test/native/pairing_test.hpp` drives the production `NativePairing` owner against
an independent private D-Bus Agent manager/device fixture. It checks registration,
explicit policy, Pair completion and unregistration on the same actual unique
sender for all three supported capabilities. WBL-B-F25 and WBL-B-F26 execute exact
accept/reject lifecycle inputs and compare observed method/resource projections.
The fixture observes the daemon's unique-sender release signal to clear remote
Agent records when a sender closes; its counters do not infer remote release
from a local function return.

Fault cases cover missing/malformed acknowledgements, explicit remote errors,
wrong peer/challenge/decision, overlapping prompts, premature Pair completion,
foreign senders, Cancel/Release, event-capacity failure, owner replacement and
cancellation while registration or discovery is pending. A full native pending
queue escalates cleanup without silently evicting ordinary work to admit another
method. One hundred successive Agent lifetimes leave no exports, pending calls,
queued replies or retained prompts. A borrowed link receives no explicit
Disconnect. A blocked UnregisterAgent and blocked owned-link Disconnect share
the caller's original cleanup deadline; repeated cancellation cannot extend it.
Native errors retain admitted names and exclude arbitrary diagnostic bodies.

These tests exercise actual libdbus messages and native component ownership.
On their own they do not execute the complete Port helper, BEAM native route,
persistent BlueZ service or virtual controller. The P03 evidence above combines
them with the public bridge and virtual-controller Pair cases.

## Native acknowledged GATT procedures

`test/native/procedures_test.hpp` executes the production typed address and
`NativeProcedure` owner against an independent GATT receiver on the private
libdbus daemon. WBL-B-F27 through WBL-B-F32 compare concrete read/write, malformed
value, remote rejection and missing/malformed response projections. The native
driver receives inputs only; expected values remain in ExUnit.

The receiver checks exact source, object path, signatures, byte arrays and typed
request-only write options. Read/write sizes 0, 1, 2, 255, 256 and 512 are exercised;
513-byte read replies and noncanonical write envelopes fail. Admission tests cover
unknown fields, invalid UUID/path/handle/generation types, stale snapshots,
conflicting selectors, duplicate UUID matches and absent procedure flags.
Malformed inputs cause no discovery or GATT request.

Each of NotPermitted, NotAuthorized, NotSupported, InProgress, InvalidOffset,
InvalidValueLength, ImproperlyConfigured, Failed, an unknown FutureCase and
NotConnected is returned by the receiver for both read and write. The envelope
keeps the bounded BlueZ name with its stable code (`remote_error` for Failed and
unknown names); a write still reports submission once, and only NotConnected
closes the sender. The retired Python unit tests previously held this table.
On 2026-09-17, `mix test --include interop --seed 0 test/interop/native_bus_test.exs`
passed 35 tests in the Linux arm64 ordinary lane and the ASan/UBSan lane (GCC
12.2.0, libdbus 1.16.2 workspace).

Lifecycle tests cover cancellation before submission, during discovery and while
an acknowledgement is pending; unavailable submission-event capacity; selected
owner loss; late replies; borrowed and owned link cleanup; and a blocked owned
Disconnect within the original deadline. One thousand successive reads on the
same connection leave no pending calls or extra listeners. No write is retried.
These results establish native component behavior through actual D-Bus messages.
On their own they do not execute Port-host dispatch, the BEAM route or BlueZ/ATT
interoperability. The P04 evidence above combines them with the public bridge
and virtual-controller read/write cases.

## Native notification ownership

`test/native/notify_value_test.hpp` checks the production mode selector and typed
PropertiesChanged decoder. Exact byte-array and Boolean variants are required;
empty through 512-byte values are retained independently of their D-Bus message.
Repeated equal values remain distinct. WBL-B-F33 through WBL-B-F37 execute exact
mode-selection inputs and outputs.

`test/native/notifications_test.hpp` drives `NativeNotifications` against an
independent private D-Bus characteristic receiver. WBL-B-F38 through WBL-B-F41
execute concrete early-value, repeated-value, notification/indication mode and
report-admission traces. Establishment results and report metadata are compared
with exact corpus values. The receiver observes actual StartNotify/StopNotify
calls and unique-sender release; local return values do not infer remote cleanup.

The boundary matrix covers one versus two early reports, cancellation during
establishment or its completion callback, remote/malformed/missing responses,
foreign senders, wrong paths/interfaces, invalidated Value, Notifying loss,
metadata changes and selected owner loss. One stream's failed report admission
preserves another stream. Sixty-four simultaneous subscriptions use one manager
listener, and 1,000 successive subscribe/cancel lifetimes leave no active entries,
paths, pending calls or extra listeners. StopNotify completes while an unrelated
ReadValue remains pending. Full native pending-call admission escalates cleanup
by closing the owned sender within the supplied deadline.

`test/native/pending_test.hpp` checks opaque generation-bound cancellation tickets:
foreign, stale, completed and default tickets cannot cancel another call, and
1,000 successive pending calls retain no tombstones. A cancelled discovery refresh
can be followed by successful establishment on the same connection.

These are actual libdbus component tests. On their own, the report callback is
not a Port transport or proof of BEAM mailbox flow control. The P05 evidence
above combines them with host/BEAM credit tests and the virtual-controller
notification and indication cases.

## Native output serialization and reservations

`test/wotex/ble/native_output_test.exs` runs the production `EncodedFrame` and
`NativeOutput` components through an owned native test executable. WBL-B-F42
through WBL-B-F44 compare exact bounded serialization outputs. Independent BEAM
JSON decoding checks native integers, Boolean/null values, UTF-8, escapes and
structured values. Native cases exercise exact line size, newline/escape growth,
invalid UTF-8, nonfinite/binary values, depth, collection and node limits.

The reservation matrix fills all 64 ordinary reply reservations, 64 report
frames and 256 control frames. Stale, foreign, default and already queued reply
tickets cannot release or reuse a reservation. One hundred thousand reservation
lifetimes leave no historical records. An eight-frame 1 MiB report backlog still
admits separate ordinary replies and a terminal control frame.

The pipe fixture fills an actual nonblocking pipe, checks retained counters under
backpressure, drains partial frames and compares the complete ordered byte-stream
hash with an independently accumulated expected hash. Reply capacity returns
only after complete transmission. Closed-reader and blocking-descriptor paths
fail explicitly. Queue byte counts measure retained encoded bytes, not total
allocator or process RSS. These tests do not execute the complete host or prove
report credit acknowledgements across the BEAM Port boundary; those remain open.

## Native value flow and terminal controls

`test/wotex/ble/native_reports_test.exs` executes `reports.hpp`, `credit.hpp`
and `output.hpp` together through actual nonblocking pipes. WBL-B-F45 through
WBL-B-F48 compare exact native admission results, complete wire frames and
remaining counters. Value reports carry cumulative sequence/byte credits;
terminal errors use the separate control reservation and precede the single
retirement barrier. A queued or partly written value cannot be acknowledged.

The native matrix checks forged metadata, stale IDs, invalid error fields,
partial writes, exact cumulative byte acknowledgements, per-stream windows,
64 active streams, 64 queued reports and the 1 MiB queued/credited byte limits.
A blocked stream preserves another stream's progress and its own report order.
Retirement discards unsent values and retains only outstanding credit records;
1,000 subscribe/report/retire/acknowledge lifetimes leave no historical records.
Ten thousand callbacks after overflow cannot queue another value or terminal.
Control exhaustion fails the shared channel rather than growing without bound.
The byte-pressure cases use explicit test-only metadata padding to reach generic
IPC bounds; they do not assert that BlueZ accepts that metadata as a characteristic.

The error-code/name shape is shared with actual SDK failures. These are native
component and wire-serialization tests. SDK notification callbacks, complete
host dispatch and actual BEAM process suspension still require their integrated
execution; this evidence does not complete the accepted Port backend.

## Native guardian startup ownership

`test/wotex/ble/native_command_test.exs` checks the fixture guardian through
actual BEAM Ports: 1,000 short commands retain exact exit status, 32 concurrent
commands retain separate groups, and inherited ignored SIGCHLD/blocked signals
cannot discard child status. An injected parent setpgid failure leaves the
child's marker file absent and returns a bounded setup failure.

`test/wotex/ble/native_guardian_startup_test.exs` and
`test/native/guardian_startup_check.c` exercise the runtime guardian's release
barrier with 1,000 short SDK processes, inherited signal state and injected group
admission failures. Both guardians establish the group before releasing their
child. The native probe checks its own process-group identity and inherited
signal state. The existing opaque-stream custody matrix remains applicable;
startup serialization grants no additional time or report credits.

## Native live Device1 query

`test/native/health_test.hpp` executes the native `health` operation against an
independent private D-Bus receiver. WBL-B-F49 through WBL-B-F55 supply exact typed
reply fields and compare values, bounded error envelopes, GetAll calls and
observed sender release. The fixture sees the original client sender, Device1
path, Properties interface and exact `s` request argument. Successful health
requires current Connected and ServicesResolved booleans plus the original
adapter/address/address-type identity.

The matrix checks missing fields, wrong variants, valid changed identities,
malformed identities, false state, duplicate and excessive properties, bounded
skipping of unknown properties, permission errors, malformed replies, deadline expiry,
late replies and explicit cancellation. No borrowed case issues Disconnect.
The cases use the actual libdbus operation/lifecycle code. On their own they do
not establish native-host routing or BlueZ/ATT interoperability; the P06 evidence
above combines them with the public bridge and virtual-controller Runtime cases.


## Native bounded discovery pages

`test/wotex/ble/native_pages_test.exs` compiles `test/native/pages_test.cpp` and
executes the production `NativePages` component through the owned command
fixture. WBL-B-F56 through WBL-B-F60 provide exact page, invalidation, foreign
cursor, eviction and 2,000-generation ledger projections. Other native cases
cover complete ordering across 1,024 characteristics, aggregate line and JSON
node limits, forged options, generation regression and exhaustion boundaries,
repeat-position token reuse, eight-collision rejection and random-source failure
without ledger mutation. The page component performs no D-Bus I/O. Complete
native host routing and the BEAM discovery API remain separate proof obligations.


## Native SDK host composition

`test/native/host_test.hpp` drives the combined `NativeHost` against an independent
private D-Bus service. Cases execute typed health, read/write, discovery,
pairing challenges and policy replies, notification overflow and cumulative
report ACKs. A held read does not postpone StopNotify or a different queued
request's timeout. Close cancels a pending StartNotify and remains admitted
with all 64 ordinary reply reservations held. Unknown characteristic flags
remain present in discovery results.

`test/native/host_process_test.hpp` executes `priv/bluez/native/main.cpp` as an
owned child with actual stdin/stdout pipes. WBL-B-F61 through WBL-B-F63 project
startup, complete discovery, explicit close, duplicate flow rejection and stdin
loss during a withheld opening response. A regression sends `close` and then
closes input before the reply: the admitted close still returns a null result
and exit status zero instead of a `cleanup_timeout` failure. Before the fix the
same trace failed its exit-status assertion on the Linux arm64 lane. A second
host regression holds `UnregisterAgent` during an explicit close after `Pair`
and then signals `Connected=false`. Link loss during that owned cleanup no
longer turns the completed close into `cleanup_timeout`; the case failed its
close-result assertion before the fix and all 35 private-bus tests pass after
it on Linux arm64. The failure first appeared when BlueZ dropped a virtual link
after a rejected pairing decision. A third regression rejects the Agent prompt
while `Pair` is still pending, which closes the owned sender by design. The
host must still report readiness of its own input descriptor so a following
`close` is read. The private-bus poll previously returned without polling the
caller's descriptors once its connection was closed or failed; the case failed
before the fix, and the bus component assertion now requires that readiness.
A fourth regression opens an owned link and withholds the Device1.Disconnect
reply, as pinned BlueZ does until its postponed link drain. The host completed
cleanup in the event-loop turn that reached its 500 ms deadline, but the loop
then exited on that same deadline with status 1 before writing the close reply;
the case failed its status and close-result assertion on Linux arm64. The loop
now writes an already completed result once at the deadline, and the ordinary
and ASan/UBSan private-bus lanes pass. The software lane first showed this as
`cleanup_timeout` for every owned close. Independent NameHasOwner queries check
client-sender release and service-sender isolation after process exit. The fixture
owns and reaps this direct, non-forking SDK child; runtime guardian process-group
custody has its separate fault corpus. This evidence does not establish native
artifact admission, BEAM native selection, Runtime report flow or virtual ATT
interoperability.


## Native executable identity admission

`test/wotex/ble/native_artifacts_test.exs` executes pure selector construction
and bounded verification of temporary executable files. WBL-B-F64 through
WBL-B-F67 cover the exact four selectors and missing, duplicate and malformed
fields without file lookup. ExUnit cases cover independent SDK/guardian digests,
field-specific missing and mismatched errors, descriptor-backed multi-chunk
hashing, final symlink and permission rejection, empty and oversized sparse
files, deadline equality and deployment replacement between explicit checks.
The deterministic module example is a real doctest. Verification starts no
process; integration with the BEAM native startup owner remains a separate
acceptance obligation.

## BEAM native artifact admission and startup

`test/wotex/ble/native_startup_test.exs` compiles the production guardian and
the deterministic `test/native/beam_startup_sdk.c` process fixture into an
OS-temporary directory. WBL-B01/WBL-B02 assertions prove that a complete native
selector cohort verifies both SHA-256 identities under the caller's original
deadline, launches the SDK only through the guardian, accepts only the exact
native ready identity, sends a fresh 128-bit lowercase session generation in
`flow_open` before `open`, and completes bounded `close`. Incomplete selectors
and an executable digest mismatch fail before either process starts. The
fixture accepts no arguments or environment configuration; it is executable
boundary evidence, not an adapter implementation or an agent harness.

This closes only BEAM admission and startup for the already implemented native
host. BEAM report acknowledgement/retirement, native build tasks, sanitizer
matrix execution and complete virtual-ATT software acceptance remain open in
WBL-P00 and later ordered packages.

## Scripted native protocol contract lane

`test/support/native_fixture.ex` compiles `test/native/scripted_host.cpp` and
the production guardian once per ExUnit run, then gives each case a private copy
of the host with its scenario file. The host links no SDK and opens no D-Bus
sender. It uses the production request parser/sequence, output reservations,
discovery cursor ledger, report credits, deferred report queue and stream
barriers; every reply, error envelope, challenge and value is a scripted input.
Its `.jsonl` ledger records the received wire operations, emitted
`write_submitted` events and the active stream count and unanswered operations
when `close` or EOF arrives.

`test/wotex/ble/dbus_bridge_test.exs`, `test/wotex/ble/stream_bridge_test.exs`
and `test/wotex/ble/runtime_stream_test.exs` launch it through the verified
native selector cohort. They assert BEAM startup/frame bounds, admission, queue
and absolute deadlines, close joining, Agent policy exchange, procedure phases,
subscription ownership, credit-backed report delivery, cancellation and
Runtime relay behavior at the native wire boundary. They are injected-contract
evidence only: D-Bus calls, BlueZ error-name mapping, StopNotify cleanup and
Agent registration are native component or virtual-controller claims. A report
for an unknown subscription closes the generation without delivery under
WBL-B02; the Python adapter lane had ignored it.

Finding fixed with this lane: the BEAM escalation sent SIGTERM to the guardian at
850 ms and SIGKILL 100 ms later, before the guardian's 250 ms group SIGKILL. An
SDK host ignoring SIGTERM and stdin survived as an orphan. Connection close now
gives the cooperative host 500 ms plus a 150 ms window for its final reply, then
hands forced termination to the guardian, and kills the guardian only if it has
not exited 500 ms after that handover. A stalled cancellation has 500 ms before
an immediate close with the same reply window. The `uncooperative` and
`close_blocked` scenarios assert `cleanup_timeout` and host process exit.

A first version handed over at 500 ms. A host that used its whole cooperative
allowance, as an owned close waiting for BlueZ Disconnect does, then lost its
successful reply to the guardian stop. The `close_drain` scenario replies 560 ms
after receiving `close`; it returned `cleanup_timeout` in three runs before the
handover moved and returns `:ok` after it.
