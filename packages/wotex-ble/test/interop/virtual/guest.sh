#!/bin/bash
set -euo pipefail
pids=()
finish() {
  result=$?
  trap - EXIT
  remaining=0
  for (( index=${#pids[@]}-1; index>=0; index-- )); do
    process=${pids[$index]}
    if kill -0 "$process" 2>/dev/null; then
      kill -TERM "$process" 2>/dev/null || true
      for attempt in $(seq 1 100); do
        kill -0 "$process" 2>/dev/null || break
        state=$(awk '{print $3}' "/proc/$process/stat" 2>/dev/null || true)
        test "$state" = Z && break
        sleep .01
      done
      state=$(awk '{print $3}' "/proc/$process/stat" 2>/dev/null || true)
      if test -n "$state" && test "$state" != Z; then
        kill -KILL "$process" 2>/dev/null || true
        result=1
      fi
    fi
    wait "$process" 2>/dev/null || true
    kill -0 "$process" 2>/dev/null && remaining=$((remaining+1))
  done
  controllers=$(find /sys/class/bluetooth -mindepth 1 -maxdepth 1 -type l | wc -l)
  test "$controllers" -eq 0 && test "$remaining" -eq 0 || result=1
  printf '{"result":%s,"owned_processes_remaining":%s,"virtual_controllers_remaining":%s}\n' "$result" "$remaining" "$controllers" > /results/guest-result.json
  sync
  /usr/lib/klibc/bin/poweroff
}
trap finish EXIT
modprobe hci_vhci
test -c /dev/vhci
test -z "$(find /sys/class/bluetooth -mindepth 1 -maxdepth 1 -type l)"
/opt/bluez/bin/btvirt -L -l2 > /results/btvirt.log 2>&1 &
pids+=("$!")
for attempt in $(seq 1 100); do test -e /sys/class/bluetooth/hci1 && break; sleep .1; done
test "$(find /sys/class/bluetooth -mindepth 1 -maxdepth 1 -type l | wc -l)" -eq 2
for controller in /sys/class/bluetooth/hci0 /sys/class/bluetooth/hci1; do
  test "$(readlink -f "$controller")" = "/sys/devices/virtual/bluetooth/$(basename "$controller")"
done
mkdir -p /run/wbl
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/wbl/bus
/usr/bin/dbus-daemon --nofork --config-file=/opt/wbl/fixture/bus.conf > /results/dbus.log 2>&1 &
pids+=("$!")
for attempt in $(seq 1 100); do test -S /run/wbl/bus && break; sleep .1; done
test -S /run/wbl/bus
/opt/bluez/libexec/bluetooth/bluetoothd --nodetach --experimental --noplugin='*' --configfile=/opt/wbl/fixture/main.conf > /results/bluetoothd.log 2>&1 &
pids+=("$!")
/opt/bluez/bin/btmon -w /results/wire.btsnoop > /results/btmon.log 2>&1 &
pids+=("$!")
/opt/sdk/bin/python -B -u /opt/wbl/fixture/native_gatt.py
