---
paths:
  - "**/*"
---

# Public boundary rules

- Refer to integrations as the consumer or consumer host.
- Do not include consumer names, internal paths, private fixtures, customer
  data, credentials, or organization-specific identifiers.
- Do not add host frameworks, persistence implementations, transport servers,
  or job runners.
- Every dependency source switch is explicit. Never select a dependency because
  a neighboring directory happens to exist.
- Public from substance: no empty placeholder modules, packages, or claims.
