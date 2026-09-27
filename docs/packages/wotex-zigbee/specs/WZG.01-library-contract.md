# WZG.01 — Coordinator host boundary

Version: 0.3.0-target. The catalogue records implementation status; hardware
qualification is separate.

## NCP architecture

**WZG1-01.** The first architecture uses a network co-processor running a qualified Zigbee stack. Elixir owns the host protocol, lifecycle, typed commands/results and consumer-facing observations. It does not implement the radio PHY/MAC timing in BEAM processes. An arbitrary IEEE 802.15.4 radio or a Thread Spinel RCP is not interchangeable with a Zigbee coordinator NCP.

The public boundary is neutral: coordinator identity/capabilities, network operations, ZDO/ZCL requests, reports, persistence/credential ports and lifecycle. Chipset framing is a backend. A product profile, home rule, canonical Thing state or safety response is not part of this package.

## First backend decision

**WZG1-02.** Start with one documented serial NCP backend. TI ZNP/Monitor-Test is the first host backend; EZSP over ASH is a separate potential backend, not a protocol synonym. Pin the exact NCP firmware, SDK/API version, serial parameters and supported commands. Open host control and vendor firmware licensing are distinct; the package must not claim full radio-stack source openness without evidence.

Primary architecture references: [TI ZNP](https://software-dl.ti.com/simplelink/esd/simplelink_cc26x2_sdk/2.30.00.34/exports/docs/zstack/html/zigbee/znp_interface.html) and [Silicon Labs NCP overview](https://docs.silabs.com/zigbee/9.1.0/zigbee-coprocessors-overview/). The first host API uses the TI CC26x2 SDK 2.30.00.34 revision; exact coordinator firmware bytes remain consumer-configured and physical firmware qualification is outstanding.

## Serial ownership

**WZG1-03.** A consumer supplies a serial port implementation. One supervised owner holds the coordinator; no global auto-discovery or silent serial-path selection occurs. Match the configured hardware identity after USB reconnect and negotiate the protocol version before restoring network use. Only an explicit command may form, erase or replace a network.

Handle fragmented/coalesced serial frames, invalid lengths/checksums, async indications and transport reset. Bound frame bytes, pending requests, report queues and deadlines. ZNP synchronous replies and later AF/ZDO confirmations are separate observations. EZSP implementations must implement their admitted ASH/version/recovery profile rather than assume an unframed serial stream. A timeout cannot be interpreted as a network reset request.

## Values and calls

**WZG1-04.** Pure values carry logical IEEE identity, endpoint, cluster, manufacturer code, direction, typed payload and caller context. The backend maps correlation/sequence tokens under finite outstanding windows. A sent serial command, APS acknowledgement, ZCL default response and attribute report are distinct result classes. No result grants consumer authorization or proves physical effect.

The first AF request seam carries raw eight-byte EUI-64 peer identity, its
current 16-bit route, endpoints, cluster, local transaction byte and bounded
caller correlation. Peer identity and caller correlation stay on the host;
ZNP receives only its defined AF fields. The consumer verifies the route to
IEEE mapping during interview and after rejoin. A route-only compatibility
call remains available but does not claim durable identity.

Credentials are resolved through explicit custody and not stored in public request values, errors or telemetry. Opaque owner handles have epochs; a replaced process cannot complete the prior owner's operation. Loading the package starts nothing; stateful owners are explicit child specifications.

## Acceptance

WZG1-T1: constructor purity and unsupported backend/version errors. WZG1-T2: serial fragmentation, garbage, async reordering and finite budgets. WZG1-T3: command/reply versus later confirmation distinction. WZG1-T4: USB removal, stale handles and recovery without forming a new network. WZG1-T5: macOS and Nerves-compatible serial adapters exercise the same neutral contract. WZG1-T6: vendor profiles remain consumer-owned and no external home-automation daemon is required.

## Implementation evidence

| Boundary | Executed evidence | Remaining evidence |
| --- | --- | --- |
| Serial adapter | `circuits_uart_test.exs` mocks the UART API and covers exact USB identity, post-open drift, open/write errors, owner cleanup and a `SYS_VERSION` handshake through `Wotex.Zigbee.Owner`. | A real coordinator on macOS and Nerves, unplug/replug, exclusive open and permissions on both hosts. |
| Host protocol | `frame_test.exs`, `owner_test.exs`, `event_test.exs` and `zdo_test.exs` exercise the bounded software profile with an independently encoded simulated peer. | Exact firmware artifact, real NCP reset/recovery and physical endpoint evidence. |
| Request identity | `data_request_test.exs` validates EUI-64, route, payload and caller correlation and sends through the simulated serial peer without placing host-only identity in the wire frame. | Interview-derived route custody, source identity resolution, manufacturer/direction semantics and credential port. |
