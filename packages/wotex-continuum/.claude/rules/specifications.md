---
paths:
  - "specs/**/*.md"
  - "priv/schemas/**/*.json"
  - "test/vectors/**/*.json"
---

# Specification rules

- WCT.01, WCT.02, and WCT.03 each have one normative owner file.
- Use MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY deliberately.
- Identify standard facts, project interpretation, and implementation choices.
- Cite exact dated W3C documents for W3C-defined meaning.
- A schema change updates vectors and compatibility rules in the same commit.
- Invalid vectors name the exact expected error code and path.
