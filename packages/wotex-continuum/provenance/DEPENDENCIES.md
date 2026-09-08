# Dependency provenance

Observed: 2026-09-08

| Dependency | Range | Runtime use | Boundary |
|---|---|---|---|
| Wotex core | `~> 0.1.0`; local verification revision `e03ea9733e30fb05caa1749dff62e57b3670be28` | validated Thing Description identity, W3C WoT vocabulary authority, and bounded JSON admission | one-way public dependency; no runtime process |
| Jason | `~> 1.4` | JSON scalar escaping for canonical and plain encoding | encoding only; source admission and duplicate detection belong to the core pipeline |
| ExDoc | `~> 0.38` | documentation generation | development only; not loaded at runtime |

Transitive dependencies are locked for repository verification. A consumer host
resolves its own release graph against the published version ranges.
