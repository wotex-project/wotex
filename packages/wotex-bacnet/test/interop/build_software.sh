#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
peer_image="${WOTEX_BACNET_PEER_IMAGE:-wotex-bacnet-peer}"
docker build --tag "$peer_image" "$repo_dir/test/interop/cstack"
docker image inspect "$peer_image" --format '{{.Id}}'
