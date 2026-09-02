---
name: mqtt-binding-proof
description: Validate the standalone MQTT binding before handoff or release.
---

# MQTT binding proof

1. Run `WOTEX_PATH_DEPS=1 mix check`.
2. Confirm coverage is at least 90 percent and documentation has no warnings.
3. Run `bin/check-boundary` independently.
4. Build the Hex archive with `WOTEX_PATH_DEPS` unset.
5. Run `bin/check-archive` and record its SHA-256 digest.
6. Confirm `git remote -v` is empty and do not push.
