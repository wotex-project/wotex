# BLE primary evidence

Research date: 2026-09-08. Audience: maintainers. The protocol contract above
distinguishes normative standards, upstream implementation behavior, inferred
integration choices and evidence still requiring hardware or SDK execution.

- [Bluetooth Core 6.3 version history](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core_v6.3/out/en/consolidated-table-of-contents%2C-acknowledgments%2C---core-configurations/version-history-and-acknowledgments.html).
- [Core 6.3 ATT](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core_v6.3/out/en/host/attribute-protocol--att-.html).
- [Core 6.3 GATT](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core_v6.3/out/en/host/generic-attribute-profile--gatt-.html).
- [BlueHeron 0.5.4 API](https://hexdocs.pm/blue_heron/0.5.4/api-reference.html).
- [BlueZ GATT API, source 2123ab772fbe97d1369fc9e179ea87c3469cf98f](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.GattCharacteristic.rst).

Research searched standards/revision availability, wire/address rules, transport
ownership, security and interoperability gaps, then reviewed upstream APIs.
Stop reason: consequential design claims have primary evidence or explicit
access limits. No physical or secure-stack execution was performed by research.

W3C [TD 1.1 Recommendation, 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
is the Thing Description baseline. [Binding Registry 2025-11-04 draft](https://www.w3.org/TR/2025/DRY-wot-binding-registry-20251104/)
does not turn a package-defined profile into a W3C Recommendation.

## Software-contract review, 2026-09-08

Pin BlueZ source and documentation to
`2123ab772fbe97d1369fc9e179ea87c3469cf98f` (2026-02-03):
[GattCharacteristic1](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.GattCharacteristic.rst),
[Device1](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.Device.rst),
[Agent1](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.Agent.rst)
and [btvirt source](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/emulator/main.c).
ReadValue/WriteValue and StartNotify/StopNotify are D-Bus operations. StartNotify
has no notify-versus-indicate selection argument; .10 deliberately rejects an
unfulfillable explicit selection on a characteristic advertising both procedures.
One persistent D-Bus sender must own notification start/stop. A transient busctl
process cannot retain that ownership.

Use [dbus-next 0.2.3](https://pypi.org/project/dbus-next/0.2.3/), released
2021-07-25, [source 74dc9706e8d0ebb17f27818b8ef9e214172514ec](https://github.com/altdesktop/python-dbus-next/tree/74dc9706e8d0ebb17f27818b8ef9e214172514ec).
This is an exact selected dependency, not a claim that it is the newest release;
native dependency audit remains mandatory. Its asyncio MessageBus is the chosen
persistent bridge boundary. The isolated VM fixture uses the inspected btvirt
`-L -l2` options and a required VHCI-enabled kernel. These are software GATT
interoperability requirements; physical RF and qualification remain separate.

## Standalone contract review, 2026-09-09

[WBL.11](../specs/WBL.11-standalone-client-and-preservation.md) records
additional source-pinned API and retained-workflow decisions. Its concrete
fixtures are specified, unexecuted acceptance data. This review does not add
an interoperability or standards-conformance result.
