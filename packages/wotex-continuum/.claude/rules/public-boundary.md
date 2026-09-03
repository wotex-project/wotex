---
paths:
  - "**/*"
---

# Public boundary rules

- Use “consumer” and “consumer host”; never add consumer-specific names.
- Never add organization-internal paths, credentials, customer data, or
  non-public source references.
- Do not add framework, persistence, job, provider, or UI dependencies.
- Run `scripts/check_public_boundary.sh` before every commit.
- Automated agents never configure or change a remote, push, tag, or publish.
