---
name: mqtt-binding-proof
description: Validate the wotex-binding-mqtt MQTT binding package before handoff or release.
---

# MQTT binding proof

Package: `packages/wotex-binding-mqtt/`. Step 1 runs from the repository root;
the other steps run inside the package directory.

1. Run `mix pkg wotex-binding-mqtt check --no-retry` (the package's full gate).
2. Confirm coverage meets the 95 percent floor and documentation has no
   warnings.
3. Run `elixir bin/check_boundary.exs`
   (`packages/wotex-binding-mqtt/bin/check_boundary.exs`) independently.
4. Build the Hex archive with `WOTEX_PATH_DEPS` unset (`mix package`).
5. Run `WOTEX_PATH_DEPS=1 mix run --no-start bin/check_archive.exs`
   (`packages/wotex-binding-mqtt/bin/check_archive.exs`) and record its
   SHA-256 digest.
6. Stop after recording local evidence. Automated agents never configure or
   remove remotes, push, create tags, publish packages, or create releases.
