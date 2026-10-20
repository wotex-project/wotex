# CoreBluetooth host v1

Version: 0.1.1. Updated: 2026-10-20. Status: accepted delivery contract.
Owner: [WBL.08](WBL.08-write-modes-and-native-hosts.md), requirements 01–04.
Implementation and executed evidence are recorded in the package catalogue.

## Native operation ownership

The host keeps one serialized operation at a time. Its explicit ticket consists
of a nonzero consumer connection generation, a non-reused request number and an
exact characteristic-route token. The SDK owner holds the peripheral and
characteristic objects for that route. A callback from another ticket, route or
generation cannot complete the operation. A timed-out or cancelled submitted
operation retires its entire SDK owner before another generation may start.

The native operation takes an explicit nonnegative elapsed time, one absolute
deadline at most 60,000 ms later, the complete selected route, at most 512 bytes,
an SDK port and a bounded result sink. It reads no clock or global configuration.
The SDK port supplies current authorization, connection/route identity, the
per-write-mode maximum length, command readiness, submission and actual retirement
state. Its callbacks are prompt, nonthrowing and non-reentrant; the SDK owner
serializes delegate events after the initiating call returns. This port does not establish
that those supplied SDK facts have been independently qualified.

Reads require a readable route and empty input. Acknowledged writes require the
write property. Commands require the distinct write-without-response property.
For either write, the complete input must fit both 512 bytes and the current SDK
maximum for its exact mode. A zero/unavailable SDK maximum refuses. No value is
split, truncated, retried or changed to another write mode.

Before a command is submitted, readiness, authorization, route, size and the
original deadline are checked again. Waiting for readiness consumes that same
deadline and emits no submitted marker. A readiness callback for another ticket
does nothing. A readiness callback is only a reason to recheck current facts;
it cannot override a currently false readiness value.

A bounded submission marker must be admitted before either write reaches the
SDK. Marker refusal sends nothing. A command succeeds with native queue evidence
only after the SDK port reports submission accepted; it never waits for or
fabricates an ATT response. An acknowledged write succeeds only on its matching
write callback. A read succeeds only on its matching bounded value callback.
Errors after the marker preserve submission uncertainty. Success is emitted at
most once, and a finished operation cannot be restarted.

Cancellation, deadline equality, clock regression, authorization loss, route or
connection loss and malformed matching callbacks fence further submission.
Retirement is requested once. Its single 500 ms budget never extends on repeated
cancellation or callbacks. A terminal result waits for confirmed owned-resource
retirement; refusal or expiry instead returns cleanup_timeout with the original
cause and submission classification. Confirmation must be observed strictly
before the cleanup deadline; equality is expired. Initiating retirement is not confirmation.
Destroying an unfinished operation is a native lifetime error, not silent cleanup.

## SDK and public client delivery

The SDK adapter must implement the port through CoreBluetooth on a dedicated
serialized callback queue, using exact peripheral/characteristic object identity.
The actual host, its explicit build inputs, public Client, permission policy,
wire revision and independent peer cases must exist before claiming that this
operation component is a usable macOS backend. Ordinary package loading must
not instantiate a manager or prompt for permission.

The adapter must consult maximumWriteValueLengthForType for the selected write
type and canSendWriteWithoutResponse before a command. The readiness delegate
does not supply an acknowledgement. CoreBluetooth cancellation is asynchronous;
the adapter must confirm its owned callbacks/objects are retired and preserve
uncertainty about work already given to the system. OS pairing/security policy,
explicit private peripheral identity and unsupported capability cells remain
part of the required adapter contract, never inferred from a UUID or paired flag.

Discovery, notifications, sleep/reset/permission loss, consumer-owned startup,
CoreBluetooth/Runtime/archive joins and installed macOS qualification remain
WBL.08 obligations. Delivering the operation component does not waive them.

The native operation component is implemented in
`packages/wotex-ble/priv/corebluetooth/native/operation.hpp`. Its fourteen-case
independent scripted-port corpus is
`packages/wotex-ble/test/native/corebluetooth_operation_test.cpp`, executed by
`corebluetooth_operation_test.exs`. This component and its tests instantiate no
CoreBluetooth manager and establish no SDK, permission or peripheral behavior.
The [operation record](../provenance/corebluetooth-operation-2026-10.md) binds
the ordinary/sanitizer runs, source identities, actual checks and omissions.

## Acceptance

| Case | Independent stimulus and falsifier |
| --- | --- |
| CB-OP1 | Read, acknowledged write and command preserve exact ticket/mode/bytes; only their matching completion evidence succeeds |
| CB-OP2 | Empty/512-byte, exact SDK maximum and one-over inputs; missing property/maximum, invalid ticket/deadline and refused marker invoke no SDK submission |
| CB-OP3 | Readiness waits, duplicate and foreign callbacks, changed size/permission/route, clock regression and deadline equality cannot send unsent work |
| CB-OP4 | Submitted timeout/cancellation preserves uncertainty; repeated cancellation cannot renew cleanup; late callbacks cannot complete a retired operation |
| CB-OP5 | Pending/confirmed/unconfirmed retirement, exact 500 ms cleanup boundary, one result and unfinished destruction are distinguished |

The [Apple write API](https://developer.apple.com/documentation/corebluetooth/cbperipheral/writevalue(_:for:type:)),
[per-mode length API](https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:))
and [readiness API](https://developer.apple.com/documentation/corebluetooth/cbperipheral/cansendwritewithoutresponse)
provide SDK vocabulary. The installed macOS 27.0 SDK headers were inspected;
that inspection does not qualify runtime permissions, a peripheral or RF behavior.
