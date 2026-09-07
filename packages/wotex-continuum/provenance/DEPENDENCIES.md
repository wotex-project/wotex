# Dependency provenance

Observed: 2026-09-07

| Dependency | Range | Runtime use | Boundary |
|---|---|---|---|
| Wotex core | `~> 0.1.0`; local verification revision `8cfda6a628b5a0efdcf489613301ec3d6eeb8c3f` | validated Thing Description identity, W3C WoT vocabulary authority, and bounded JSON admission | one-way public dependency; no runtime process |
| Jason | `~> 1.4` | JSON scalar escaping for canonical and plain encoding | encoding only; source admission and duplicate detection belong to the core pipeline |
| ExDoc | `~> 0.38` | documentation generation | development only; not loaded at runtime |

Transitive dependencies are locked for repository verification. A consumer host
resolves its own release graph against the published version ranges.
