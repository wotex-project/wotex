# Dependency provenance

Observed: 2026-09-02

| Dependency | Range | Runtime use | Boundary |
|---|---|---|---|
| Wotex core | `>= 0.1.0-dev and < 0.2.0`; verification revision `3676e71ed5b3b15e002bf4a05cc1b856a75dd8d9` | validated Thing Description identity and W3C WoT vocabulary authority | one-way public dependency; no runtime process |
| Jason | `~> 1.4` | bounded JSON parsing and scalar escaping | decoded objects are normalized and duplicate-checked before construction |
| ExDoc | `~> 0.38` | documentation generation | development only; not loaded at runtime |

Transitive dependencies are locked for repository verification. A consumer host
resolves its own release graph against the published version ranges.
