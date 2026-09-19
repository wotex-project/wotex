# Records the exact guest kernel, BlueZ, QEMU, BEAM, peer and package identity
# inside the software fixture image. Mix copies this output into its workspace.
command = fn executable, arguments, environment ->
  {output, 0} = System.cmd(executable, arguments, stderr_to_stdout: true, env: environment)
  String.trim(output)
end

digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end
lower = [{"PATH", "/opt/lower/elixir/bin:/opt/lower/erlang/bin:/usr/local/bin:/usr/bin:/bin"}]

paths = ~w(/boot/vmlinuz-6.1.0-53-arm64 /boot/initrd.img-6.1.0-53-arm64 /boot/config-6.1.0-53-arm64
  /module/hci_vhci.c /lib/modules/6.1.0-53-arm64/kernel/drivers/bluetooth/hci_vhci.ko
  /opt/bluez/bin/btvirt /opt/bluez/bin/btmon /opt/bluez/libexec/bluetooth/bluetoothd
  /usr/bin/dbus-daemon /usr/bin/qemu-system-aarch64 /usr/bin/qemu-img
  /opt/wbl/bin/wotex-ble-public-peer
  /opt/wbl/native/output/bin/wotex-ble-host /opt/wbl/native/output/bin/wotex-ble-guardian
  /opt/wbl/native/output/lib/libdbus-1.so.3 /opt/wbl/native/native-manifest.json)

report = %{
  "bluez_version" => command.("/opt/bluez/libexec/bluetooth/bluetoothd", ["--version"], []),
  "qemu_version" => command.("qemu-system-aarch64", ["--version"], []),
  "compiler" => command.("cc", ["--version"], []),
  "module" => command.("modinfo", ["-k", "6.1.0-53-arm64", "hci_vhci"], []),
  "elixir_latest" => command.("/usr/local/bin/elixir", ["--version"], []),
  "elixir_lower" => command.("/opt/lower/elixir/bin/elixir", ["--version"], lower),
  "peer" => command.("/opt/wbl/bin/wotex-ble-public-peer", ["--version"], []),
  "packages" =>
    String.split(command.("dpkg-query", ["-W", "-f=${Package}=${Version}\\n"], []), "\n"),
  "sha256" => Map.new(paths, &{&1, digest.(&1)})
}

IO.binwrite(:stdio, [JSON.encode!(report), "\n"])
