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
