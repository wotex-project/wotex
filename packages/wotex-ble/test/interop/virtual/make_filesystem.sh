#!/bin/bash
set -euo pipefail
root=$(mktemp -d /tmp/wbl-root.XXXXXXXX)
trap 'rm -rf "$root"' EXIT
tar -xf /work/rootfs.tar -C "$root"
truncate -s 6G /work/rootfs.raw
mkfs.ext4 -F -d "$root" /work/rootfs.raw
