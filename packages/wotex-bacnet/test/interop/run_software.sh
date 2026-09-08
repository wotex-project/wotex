#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
peer_image="${WOTEX_BACNET_PEER_IMAGE:-wotex-bacnet-peer}"
results_dir="${WOTEX_BACNET_RESULTS_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/wotex-bacnet-software.XXXXXX")}"
mkdir -p "$results_dir"
export WOTEX_BACNET_RESULTS_DIR="$results_dir"
docker image inspect "$peer_image" > "$results_dir/peer-image.json"
peer_revision="$(docker image inspect "$peer_image" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')"
[[ "$peer_revision" == '3603048350b8ba543ec76cf6aa8a232b3f4d442d' ]] || { echo 'Required pinned C-stack image is missing; run build_software.sh' >&2; exit 1; }
peer_port="${WOTEX_BACNET_PEER_PORT:-57808}"
peer_id="$(docker run --detach --publish "127.0.0.1:$peer_port:47808/udp" "$peer_image")"
cleanup() {
  docker logs "$peer_id" > "$results_dir/peer.log" 2>&1 || true
  docker inspect "$peer_id" > "$results_dir/peer-container.json" || true
  docker rm --force "$peer_id" >/dev/null
}
trap cleanup EXIT
for attempt in {1..50}; do
  if docker exec "$peer_id" sh -c 'grep -q ":BAC0 " /proc/net/udp'; then break; fi
  if [[ "$attempt" == 50 ]]; then echo 'Required C-stack UDP listener did not start' >&2; exit 1; fi
  sleep 0.1
done
docker exec "$peer_id" cc --version > "$results_dir/native-compiler.txt"
docker exec "$peer_id" dpkg-query --show > "$results_dir/native-packages.txt"
port_mapping="$(docker port "$peer_id" 47808/udp)"
export WOTEX_BACNET_INTEROP_PORT="${port_mapping##*:}"
cd "$repo_dir"
elixir --version | tee "$results_dir/toolchain.txt"
shasum -a 256 mix.lock docs/specs/fixtures/contract-v1.json test/fixtures/stack_lifecycle_v1.json test/fixtures/read_write_software_v1.json test/software/lifecycle_stress_test.exs test/interop/cstack/Dockerfile > "$results_dir/source-sha256.txt"
mix test --include interop --include software --seed 470127 test/interop/cstack_test.exs test/software/lifecycle_stress_test.exs test/wotex/bacnet/stack_lifecycle_test.exs test/wotex/bacnet/character_string_test.exs test/wotex/bacnet/service_boundary_test.exs | tee "$results_dir/tests.log"
printf 'Software evidence: %s\n' "$results_dir"
