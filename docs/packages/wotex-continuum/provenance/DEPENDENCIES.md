# Dependency provenance

Reviewed cohort: 2026-09-14

| Dependency | Declared range | Reviewed version or cohort | Runtime use and boundary |
|---|---|---|---|
| Wotex core | `~> 0.1` | exact 0.1.0 candidate archive, source revision emitted by the archive check | validated Thing Description identity, W3C WoT vocabulary authority, and bounded JSON admission; one-way public dependency with no runtime process |
| Jason | `~> 1.4.5` | direct floor and repository lock 1.4.5 | JSON scalar escaping for canonical and plain encoding; source admission and duplicate detection belong to the core pipeline |
| ex_json_schema | core transitive `~> 0.11` | repository lock 0.11.5 | core schema implementation dependency; not called directly by Continuum |
| Decimal | ex_json_schema transitive `~> 3.0` in the locked cohort | repository lock 3.1.1 | parser/advisory boundary pinned and tested by Continuum; not a Continuum numeric representation |
| ExDoc | `~> 0.38` | repository lock 0.40.3 | documentation generation only; not loaded at runtime |

The exact lock is enforced by the default gate. The archive check builds the
same Continuum candidate once, installs the locked cohort in independent
consumers, and separately fixes the direct Jason dependency to its 1.4.5 floor.

The arbitrary lowest transitive graph allowed by the core package is not part
of that floor claim. Early ex_json_schema 0.11 releases allow Decimal 2.x,
which is outside the reviewed Decimal parser and advisory boundary. Tightening
the core dependency range belongs to Wotex core. A consumer resolves its own
release graph against published ranges and must review any cohort other than
those named here.
