---
paths:
  - "packages/wotex-directory/**"
  - "docs/packages/wotex-directory/**"
---

# Public boundary rules (wotex-directory)

- Refer to integrations as the consumer or consumer host.
- Do not include consumer, company, or product names, absolute machine paths,
  organization-internal paths, private fixtures, customer data, credentials,
  or organization-specific identifiers. Sibling packages are referenced by
  package name; relative paths inside this repository are allowed.
- Do not add host frameworks, persistence implementations, transport servers,
  or job runners.
- Every dependency source switch is explicit (`WOTEX_PATH_DEPS=1`). Never
  select a dependency because a neighboring directory happens to exist.
- Public from substance: no empty placeholder modules, packages, or claims.
