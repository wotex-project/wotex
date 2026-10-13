# Wotex Profiles usage rules

These rules describe the completed public target contract. The package
catalogue records implementation status separately.

- Supply complete `Wotex.Profiles.Limits` selections and explicitly selected
  profile/definition data. Constructors do not discover or scan a catalogue.
- Use `Wotex.Profiles.Profile`, `Wotex.Profiles.Definition`,
  `Wotex.Profiles.Definitions` and `Wotex.Profiles.Unit` for reader values.
  Unsupported operators, duplicate fields, numeric rounding and malformed
  native values return structured errors; they never weaken a constraint.
- Keep original byte custody separate from semantic identity. Native values
  revalidate and rehash, clearing raw identity; annotations do not affect the
  semantic digest.
- Use `Unit.convert/4` only for exact C02 integer/decimal coordinates.
  Repeating fractions and budget/coefficient overflow refuse; no rounding or
  primitive coercion is installed.
- Quantity kinds and model data belong to the consumer. Equal dimensions do
  not establish equal meaning, calibration, model truth or device support.
- Loading the library starts no process and performs no I/O. References are
  opaque identities, not fetch locations or module names.
- Verify installer-owned registrations with `Binding.new/2`; changed selector,
  operation, capture or raw-value contracts cannot retain the old digest.
  Independently qualify their actual decoder correspondence.
- A reader value, match, normalized proposal or authoring report grants no
  authority. Consumers own installed bindings, current capture, qualification,
  credentials, canonical Thing state, persistence and effects.
- Use the documented public APIs, preserve source/quality provenance and
  match errors by their fixed code/path. Planned compiler and authoring APIs
  remain separately identified in the specification catalogue.
