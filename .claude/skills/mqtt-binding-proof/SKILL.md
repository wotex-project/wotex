---
name: mqtt-binding-proof
description: Validate the standalone wotex-binding-mqtt MQTT binding before handoff or release.
---

# MQTT binding proof

Run from inside `packages/wotex-binding-mqtt/`.

1. Run `WOTEX_PATH_DEPS=1 mix check`.
2. Confirm coverage is at least 90 percent and documentation has no warnings.
3. Run `bin/check_boundary.exs`
   (`packages/wotex-binding-mqtt/bin/check_boundary.exs`) independently.
4. Build the Hex archive with `WOTEX_PATH_DEPS` unset.
5. Run `bin/check_archive.exs`
   (`packages/wotex-binding-mqtt/bin/check_archive.exs`) and record its
   SHA-256 digest.
6. Stop after recording local evidence. Automated agents never configure or
   remove remotes, push, create tags, publish packages, or create releases.
