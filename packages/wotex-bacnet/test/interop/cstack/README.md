# Independent BACnet C fixture

`peer.c` links the pinned BACnet C stack from
`docs/specs/fixtures/software-sources-v1.json`. The production client remains
BEAM BACstack. This executable owns one BACnet/IP endpoint, one UDP control
endpoint and the SDK's device/transaction/subscription state. It runs only when
the software test explicitly starts it.

The fixture uses device instance 123 and disposable Analog Output 1. Reads,
writes, priority release, Who-Is/I-Am and object COV use upstream service
handlers and codecs. Property COV uses the SDK's independent wire codecs and
first-party bounded subscription state described below. The upstream demo has
no SubscribeCOVProperty handler.

## Build and process contract

Verify the SDK archive SHA-256 before extraction. Configure this directory with
`-DWOTEX_BACNET_STACK_SOURCE=ABS`, where ABS is the verified source directory,
then build `wotex-bacnet-peer` and run CTest. CMake requires Linux, static linkage
and BACnet/IPv4. Routing, IPv6, MS/TP, secure connect, segmentation and SDK demo
applications are disabled. `-DWOTEX_BACNET_SANITIZE=ON` instruments both the
fixture and linked SDK with ASan/UBSan and frame pointers. A successful normal
build does not substitute for that lane.

The executable takes exactly `INTERFACE BACNET_PORT CONTROL_PORT DURATION_MS`.
Ports are distinct integers from 1 through 65535. The interface name is explicit
and at most 15 bytes. Duration is 1000 through 600000 milliseconds measured with
CLOCK_MONOTONIC. Expiry exits with status 75. SIGINT, SIGTERM or the `quit`
control command closes the sockets and SDK state and exits zero. Readiness is
one JSON line emitted after both sockets are bound. No request payload is logged.

The software runner requires `--version` to report the fixture protocol version
and the SDK's compiled header version without opening a socket. Its final
`cleanup` JSON event must report actual closed-descriptor checks, object and
Property subscriber counts, active SDK Invoke IDs and remaining Analog Output
objects. A successful signal or exit code alone cannot replace those counts.
The SDK's `PRINT_ENABLED` build definition is zero for this fixture, so stdout
contains fixture readiness and cleanup records. Sanitizer diagnostics remain
visible on stderr and fail the lane.

`Dockerfile.software` consumes an explicit build context containing the verified
`source.tar.gz` and the six C/CMake fixture files. It builds separate `/normal`
and `/sanitizer` binaries and static SDK libraries, runs both native CTest
boundaries for each, and defaults to the sanitizer peer. The image retains the
compiler, linker, libc and CMake metadata needed by the software manifest. Its
package-manager inputs are recorded after build; a pinned base digest and SDK
archive do not imply a bit-identical image.

`shutdown_test.exs` is an explicit terminal fixture lane with only the
`peer_shutdown` tag. Ordinary tests and the shared interop/software lane exclude
that tag, because it closes its peer. The runner starts a separate owned peer,
then selects this file with `--include peer_shutdown`. WBA-CP25 establishes both object
and Property subscriptions, observes pending confirmed Invoke IDs while the
target client is suspended, and quits the peer with those resources live.
After client resume, a real read must time out and local close must release its
owned processes/socket. The runner independently requires the peer's final
zero-resource JSON event, exit zero and absent owned container. The ExUnit
receipt alone cannot establish native process cleanup.

The runner publishes both container ports only on its local loopback address.
The fixture binds its control endpoint within that disposable container. COV
storage is limited to 16 object subscriptions and 16 destination addresses,
plus 16 separate Property subscription records. Confirmed
notification transactions use the SDK's finite table, a 200 ms retry interval
and two retries. The control endpoint has a fixed 129-byte receive buffer and
processes at most four messages per protocol-loop iteration.

## Control messages and observations

Messages contain canonical unsigned decimal fields separated by single spaces,
with at most one final LF. A message is at most 128 bytes. Embedded NUL, signs,
leading zeroes, extra fields and integer overflow are invalid. Nonces cover the
full uint32 range. Responses are JSON objects of at most 2048 bytes, echoing the
nonce and reporting the actual process ID. Malformed control returns only
`{"error":"invalid_control"}`.

| Command | Effect |
| --- | --- |
| `stats NONCE` | Read current counters, object value, priority and resource counts |
| `fault register_ack COUNT NONCE` | Drop the next COUNT successful new-registration ACKs after the SDK applies them |
| `fault renew_ack COUNT NONCE` | Drop renewal ACKs after the SDK renews the matching record |
| `fault cancel_ack COUNT NONCE` | Drop cancellation ACKs after the SDK handles deletion |
| `fault cancel_request COUNT NONCE` | Drop cancellation requests before the SDK changes its registry |
| `quit NONCE` | Return a final snapshot, then close the process |

COUNT is 0 through 255 and replaces that fault's remaining count. Zero clears
it. Other fault settings are unchanged. Faults affect only the named protocol
path; the control reply itself is sent normally.

`object_subscribers` decodes the upstream handler's actual
Active_COV_Subscriptions representation. `property_subscribers` counts the
live first-party table; `active_subscribers` sums both. `active_invoke_ids` comes from the
SDK transaction table. Registration, renewal and cancellation counters require
a successful ACK generated by the SDK; cancellation counts only a matching
record. A linker wrapper observes encoded SDK output and applies ACK loss before
the actual UDP send. `control_acks` and `notifications` count successful sends,
including notification retransmissions. `notification_acks` requires the
received Invoke ID and source to match an actual SDK transaction. Dropped ACKs,
dropped requests and failed sends have separate counters. All uint64 counters
saturate; none wraps.

Read/write/Who-Is counters count handler invocations, not successful remote
effects. `present_value` and `priority` read the actual Analog Output state.
`max_rss_kib` is Linux getrusage's process peak RSS. It is not current heap size
or proof that a resource was released. A zero client listener count does not
imply a zero server subscriber count.

## Executable scope

CTest case WBA-CP01 checks control parsing and counter boundaries.
`test/interop/cstack_cov_test.exs` executes WBA-CP02 through WBA-CP09 through the
public library: discovery/batch/write/readback/release, confirmed and unconfirmed
object COV, finite renewal and four loss scenarios. A second actual BACnet
client writes the object. Tests assert Present_Value and Status_Flags, actual
ACK and subscriber counts, exact native cleanup and finite server expiry when
cancellation cannot arrive. The selected suite requires
`WOTEX_BACNET_INTEROP_PORT` and `WOTEX_BACNET_CONTROL_PORT`; missing setup fails.
It has both `interop` and `software` tags and is excluded from ordinary unit runs.

CTest WBA-CP10 checks bounded Property service decoding and selector policy.
`test/interop/cstack_property_test.exs` executes WBA-CP11 through WBA-CP21:
confirmed/unconfirmed delivery, per-subscription increment tracking,
Status_Flags selection, equal reports after renewal, capacity rejection without
eviction, unsupported selectors, public Runtime observation/stop and all four
registration/renewal/cancellation loss controls. Runtime stop retains the
original association when the selected stop Form contains a different target.

`test/software/cov_lifecycle_stress_test.exs` binds WBA-ST03 to 100 receiver
deaths, with 25 cycles in each object/Property and confirmed/unconfirmed mode.
One independent Property subscription remains live throughout. Every cycle
checks actual cancellation and server counts, both local subscription processes,
captured lease/renew timers and settled client control/APDU/listener tables.
Final close checks all six stack processes and its UDP socket. The JSON receipt
records per-cycle elapsed cleanup, tracked BEAM heap/process memory and native
peak RSS separately. It requires the explicit `WOTEX_BACNET_RESULTS_DIR`.

The existing Dockerfile and shell entry points run the upstream read/write demo.
They do not select this instrumented fixture or implement the required Mix
workspace/manifest contract. Final WBA-P06 acceptance also needs the complete
fault workflow and supported source/archive cohorts.

## Pending Runtime establishment

WBA-CP22–CP24 require actual C-peer registration with its successful ACK
discarded. The public Runtime child must remain in opening state while the
server owns that record. Killing the final Runtime owner, final receiver or
callback worker must cancel the exact record and release the captured opening,
relay, native subscription, listener and stack processes within one local
cleanup budget. The test observes actual socket release and cancellation of
captured control/opening timers. A peer registration followed by local silence
does not establish cleanup. Each case must observe a matching server
cancellation and zero remaining subscribers and Invoke IDs.

## Property COV fixture

The Property COV fixture uses the pinned SDK's SubscribeCOVProperty and COV
notification codecs, with first-party server subscription state. It admits
Analog Output 1 Present_Value (85) and Status_Flags (111), with no array index.
Other object/Property selectors receive the corresponding BACnet Error. This
limited fixture profile does not imply a general Property-COV server.

Its table has 16 entries, separate from the SDK's 16 object-COV entries. A key
contains the complete source address, subscriber process ID, object and Property
selector. Matching renewal updates that record; matching cancellation removes
it and its pending confirmed transaction. Cancellation of an absent record
succeeds. Active object and Property subscriptions are reported separately and
their sum is `active_subscribers`.

Registrations have a 2 through 86400 second lease measured from the accepted
request using CLOCK_MONOTONIC. A renewal replaces that deadline. Expiry, cancel
and process close release the exact entry and Invoke ID. A finite initial report
is requested after each accepted registration or renewal. At most one confirmed
notification is pending per entry; changes during that exchange are evaluated
against the latest object state after the transaction settles.

Present_Value notifications contain the selected value plus Status_Flags.
Status_Flags subscriptions contain only that Property. Numeric increments are
finite and positive, and apply to Present_Value only; omission uses the object's
COV increment. The threshold is the absolute difference from the last report.
A Status_Flags change reports independently of the numeric threshold. A selected
Status_Flags subscription never gains Present_Value notifications.

Service requests have a 64-byte ceiling and must exactly match the SDK's
canonical re-encoding after decoding. Trailing bytes, partial optional fields,
malformed values and segmented requests are rejected before state mutation.
This canonical restriction is a fixture policy. Notification encoding has a
fixed 512-byte buffer. Capacity exhaustion returns a resource Error without
replacing another subscription. The same registration, renewal and cancellation
loss controls apply at the actual Property handler's ACK/send boundary.
