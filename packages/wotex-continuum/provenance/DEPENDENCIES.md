# Dependency provenance

Observed: 2026-09-02

| Dependency | Range | Runtime use | Boundary |
|---|---|---|---|
| Wotex core | `~> 0.1.0`; local verification revision `4301392f3b306c30d31c01977abf4b6d9db838e8` | validated Thing Description identity and W3C WoT vocabulary authority | one-way public dependency; no runtime process |
| Jason | `~> 1.4` | bounded JSON parsing and scalar escaping | decoded objects are normalized and duplicate-checked before construction |
| ExDoc | `~> 0.38` | documentation generation | development only; not loaded at runtime |

Transitive dependencies are locked for repository verification. A consumer host
resolves its own release graph against the published version ranges.
