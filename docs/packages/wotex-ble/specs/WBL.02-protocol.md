---
spec:
  id: WBL.02
  title: "BLE protocol and graduation contract"
  status: accepted
  version: 1.0.1
  owner: wotex-ble
  updated: 2026-09-09
---

# WBL.02 BLE protocol and graduation contract

Bluetooth Core 6.3, adopted 2026-05-05, Vol 3 Parts F and G is the ATT/GATT
baseline. BlueHeron 0.5.4 (2025-03-31) documents peripheral/server and low-level
HCI/ATT; a complete high-level central client API was not established. Its
application-owned transport startup cannot become an unconditional runtime
dependency of this process-free library. The first real central boundary should
use BlueZ D-Bus, or an explicitly configured cross-platform central client.

An address retains peer identity/address type, service UUID, characteristic
UUID and optional handle/instance. A UUID alone is not a unique characteristic
instance. Normalize 16/32-bit UUIDs to the Bluetooth base UUID; ATT serializes
2- or 16-byte UUIDs, expanding 32-bit inputs. Handles are 1..65535. Attribute
values are at most 512 bytes; negotiated MTU bounds each operation's PDU.
Protocol integers are little-endian; application value encoding is explicit.

One outstanding request is allowed per ATT bearer. After the 30-second ATT
transaction timeout the bearer cannot be reused. Prepared-write failures must
cancel the transaction rather than silently execute a partial value. Indications
require confirmation. CCCD 0x2902 is two bytes: bit0 notifications, bit1
indications; reserved bits fail. CCCD state and persistence are client-specific.

BlueZ remote GATT ReadValue, WriteValue, StartNotify and StopNotify are real
operations with structured D-Bus errors. Acquired descriptors are owned and
closed explicitly and invalidated on reconnection. Service removal, permission
errors, authentication errors and bus loss must stop pending work. Borrowed
transport resources remain consumer-owned; owned subscriptions stop on owner
death. No simulator is selected when hardware is unavailable.

WoT mappings here are a Wotex profile, not a standardized Bluetooth binding:
Property read/write select characteristic procedures; observations/events select
notification or indication explicitly. Preserve all unrelated Form extensions.

Acceptance: UUID/address/value vectors, truncated ATT frames, MTU boundaries,
wrong response handles, confirmations, cancel/cleanup, real BlueZ permission
and disconnect failures, and an explicitly configured controller/peripheral
interoperability suite. Simulated bytes do not prove RF or GATT interoperability.

## Common library rules

Use structured credential-free Error values, explicit finite budgets, immutable
address/value maps, no Application callback and no implicit runtime selection.
Compatibility callbacks are capabilities/connect/send/receive/disconnect/health_check/
subscribe/unsubscribe. A consumer port failure, malformed return or missing
transport is an error; never select simulation. Telemetry event prefixes are
[:wotex, :ble, ...] with bounded non-secret measurements. Compatibility claims require differential scenarios for the exact advertised API.
