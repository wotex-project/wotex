---
paths:
  - "packages/wotex-continuum/**"
  - "docs/packages/wotex-continuum/**"
---

# Public boundary rules (wotex-continuum)

- Use “consumer” and “consumer host”; never add consumer-specific names.
- Never add consumer, company, or product names, organization-internal paths,
  absolute machine paths, credentials, customer data, or non-public source
  references. Sibling packages are referenced by package name; relative paths
  inside this repository are allowed.
- Do not add framework, persistence, job, provider, or UI dependencies.
- Run `elixir bin/check_boundary.exs` from `packages/wotex-continuum/`
  (`packages/wotex-continuum/bin/check_boundary.exs`) before every commit.
- Automated agents never configure or change a remote, push, tag, or publish.
