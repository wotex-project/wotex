# Public BLE and Runtime virtual GATT evidence

The explicit public fixture extends the native virtual-controller fixture with
Wotex BLE and Wotex Runtime running inside the same isolated Linux guest. It
requires adjacent `wotex`, `wotex-runtime`, and `wotex-ble` source packages and
records every copied source file's SHA-256 and executable mode. This is an
explicit development use of `WOTEX_PATH_DEPS=1`.

```sh
python3 test/interop/public_machine.py build /absolute/disposable/workspace
python3 test/interop/public_machine.py run /absolute/disposable/workspace
```

The native BlueZ, Linux, QEMU, controller and D-Bus pins and isolation boundaries
are defined in [virtual-controller.md](virtual-controller.md). Build additionally
compiles [Hex 2.5.1](https://github.com/hexpm/hex/releases/tag/v2.5.1) and
[Rebar3 3.27.0](https://github.com/erlang/rebar3/releases/tag/3.27.0) separately
under each supported runtime. Their source archives are pinned to SHA-256
`bdd6ef2015aa6e50a1c21212e098e8cbe7317da65f067955d154d890532742ae` and
`985cae6e957334cfa549190b9f5efb9185c184a18fc181c87b8dde096ba79f38` respectively.
The build preserves package lockfiles, verifies archive hashes, and records the
immutable Linux image identifier and filesystem artifact hashes. Runtime versions
are recorded from inside the guest, rather than inferred from host tools.

The independent GATT application exposes a runner-owned Unix control socket for
setting stimuli and reading counters. The library never consumes that socket's
responses. Its first-party SDK opens its own D-Bus sender and executes actual
BlueZ discovery, pairing and GATT procedures over the two virtual controllers.
The public test lane uses neither an injected native backend nor a replacement
Runtime transport. The fixture's ownership monitor records actual D-Bus sender,
Agent and notification-session acquisition and cleanup.

Each runtime must execute all ten public cases in `bluez_test.exs` and
`bluez_runtime_test.exs`. A machine-readable ExUnit report identifies every case;
zero cases, skipped cases, missing reports, nonzero test exit or failed native
cleanup cannot pass. These cases cover typed read/write and denied mutation,
duplicate characteristic instances, stale generation rejection, equal notify and
confirmed indicate values, two independent senders, receiver death, pairing
accept/reject/timeout, and real ConsumedThing Property/Event values, context,
media and error projection. Explicit `contentType` is rejected according to the
native profile; omitted `contentType` preserves typed BLE conversion semantics.

This is BlueZ-to-BlueZ virtual-wire evidence with an independent GATT application,
not an independent protocol-stack claim. This lane does not accept WBL-P08's
1,000-operation, lifecycle stress, complete native-audit or final package matrix.
Those remaining software obligations have their own ordered work package.
