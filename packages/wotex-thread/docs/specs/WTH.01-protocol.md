# WTH.01 Thread protocol and graduation contract

OpenThread v2026.09.0, commit 5c8c318627954c99cd1a957a290bbd4b1027d04b
(2026-08-31), is the executable reference. The complete Thread standard text
was not reviewed; no Thread certification claim is made. Thread owns IPv6
networking, not application Property read/write semantics. CoAP or Matter
retains application-level ownership above Thread.

An Operational Dataset is at most 254 bytes. Parse type/length/value bytes
with exact lengths, no truncation and no duplicate known or unknown TLVs.
Network Key and PSKc are 16 bytes; Extended PAN ID is 8 bytes. Network names
contain 1..16 UTF-8 bytes without control characters. Preserve unknown TLVs
as opaque values; validate known fixed widths and active/pending distinctions.
Network keys and raw datasets must never appear in inspect/errors/telemetry.
Dataset syntactic validity is not network completeness; otDatasetIsValid and
management callbacks decide complete active/pending applicability.

The native daemon boundary is an explicit caller-configured Unix socket to
ot-daemon. RCP puts the stack on the host; NCP owns it on the co-processor;
Spinel is a management protocol, not an application binding. The package does
not start a system daemon, choose a radio or configure a machine implicitly.
Command output is bounded, timeouts terminate the socket, and errors cannot
be mistaken for successful output. Disconnect and owner death release owned
resources. Borrowed controller/radio resources remain with the consumer.

Read-only state/version/network inspection is the first daemon profile.
Do not expose production dataset updates as unrestricted ot-ctl dataset set:
OpenThread restricts such CLI writes to first-device network formation or tests
because invalid combinations may pass. Production management updates require
validated SDK APIs, callback completion and explicit authorization. A CLI Done
response does not prove a network-wide asynchronous change is effective.

WoT Forms must name the actual application protocol. Thread-specific metadata
can describe network reachability in a library profile but cannot invent
Thread-native readproperty/writeproperty messages. Preserve Form extensions.

Acceptance: duplicate/truncated/oversized dataset properties, UTF-8 and field
width boundaries, active/pending completeness distinctions, credential redaction,
Unix-socket partial responses/errors/timeouts/owner death, read-only native-daemon
interoperability, and explicitly opted-in radio tests. Simulator-only contracts
do not establish Thread networking or application transport parity.

## Common library rules

Use structured credential-free Error values, explicit finite budgets, immutable
address/value maps, no Application callback and no implicit runtime selection.
Compatibility callbacks are capabilities/connect/send/receive/disconnect/health_check/
subscribe/unsubscribe. A consumer port failure, malformed return or missing
transport is an error; never select simulation. Telemetry event prefixes are
[:wotex, :thread, ...] with bounded non-secret measurements. Consumer migration
requires differential scenarios against both implementations before replacement.
