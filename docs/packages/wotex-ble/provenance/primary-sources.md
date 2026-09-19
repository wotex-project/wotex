# BLE primary sources

The selected software platform is BlueZ 5.85 commit
`2123ab772fbe97d1369fc9e179ea87c3469cf98f`, with the libdbus 1.16.2 C API.
[WBL.07](../specs/WBL.07-native-backend.md) records verified source archive hashes,
compiler/runtime lanes and the separate permitted fixture dependencies.

- [Bluetooth Core 6.3 ATT](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core_v6.3/out/en/host/attribute-protocol--att-.html)
  and [GATT](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core_v6.3/out/en/host/generic-attribute-profile--gatt-.html)
  define the protocol; BlueZ owns their wire execution.
- [GattCharacteristic1](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.GattCharacteristic.rst)
  defines ReadValue/WriteValue and StartNotify/StopNotify. StartNotify has no
  notify/indicate selector; Value changes also follow reads. The binding preserves
  source uncertainty and cannot claim an ATT procedure from a D-Bus signal.
- [Device1](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.Device.rst)
  and [Agent1](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.Agent.rst)
  define explicit connection/pairing and pending user decisions. The package never
  removes bonds, requests default Agent authority or claims link security from a
  paired flag.
- [Device implementation](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/src/device.c)
  owns Pair sender-loss behavior and the two-second disconnect timer. Local
  one-second sender cleanup and later BlueZ link drain are separate observations.
- [libdbus connections](https://dbus.freedesktop.org/doc/api/html/group__DBusConnection.html)
  define private ownership, asynchronous pending calls and watch/timeout event-loop
  integration. .13 selects this C boundary and pins its archive, not a Python
  MessageBus in production.
- [btvirt](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/emulator/main.c)
  supplies virtual LE controllers; the mandatory fixture checks VHCI support.
  Its independent GATT provider uses the
  [GDBus connection API](https://docs.gtk.org/gio/class.DBusConnection.html)
  from the recorded guest GLib/GIO package and first-party C++ source. This is a
  separate D-Bus implementation from the production libdbus client and adds no
  Python fixture exception.

BlueHeron's direct HCI stack is a different owner boundary; it is not a fallback
for this explicitly BlueZ central profile. Physical RF and Bluetooth qualification
remain outside the required software lane.

W3C [TD 1.1 Recommendation](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
owns Thing Description semantics. A package-defined protocol Form profile is
not W3C certification. Source review supports API choices; execution evidence
belongs to [executable-evidence.md](executable-evidence.md). Native .13 specifies
library policy for limits, credits, error classes and ownership, not extra
protocol-standard guarantees.

The packaged nlohmann/json 3.11.3 header uses its SAX interface to enforce
C07 bounds during tree construction. The upstream [security advisory list](https://github.com/nlohmann/json/security/advisories)
contains no published advisory at this source review; this observation is not
a security guarantee. Only JSON input is admitted by this boundary.
