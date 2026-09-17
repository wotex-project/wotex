#!/bin/bash
set -euo pipefail
export PATH=/opt/bluez/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
mountpoint -q /proc || mount -t proc proc /proc
mountpoint -q /sys || mount -t sysfs sysfs /sys
mountpoint -q /dev || mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /results
mountpoint -q /dev/pts || mount -t devpts devpts /dev/pts
modprobe 9pnet_virtio
mount -t 9p -o trans=virtio,version=9p2000.L fixture /results
exec /bin/bash /opt/wbl/fixture/guest.sh
