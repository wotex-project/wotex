---
paths:
  - "lib/**/*.ex"
  - "test/**/*.exs"
  - "docs/**/*.md"
  - "priv/vectors/**/*.json"
---

# W3C WoT terms and claims

- Use `Thing`, not a hardware-category synonym, when the W3C abstraction is
  intended.
- Use `Property`, `Action`, and `Event` only for their interaction affordance
  meanings.
- Spell `Thing Description` in full before using `TD` in prose.
- Keep W3C-standard fields separate from project-authored protocol fields.
- Every standards claim names an exact publication revision and section.
- A vector is evidence only for the claim ID it names.
- Fixture presence and schema validity do not establish interoperability,
  certification, or complete standard conformance.
- W3C text is cited or linked. Do not copy normative prose into source.
