# W3C Thing Model 1.1 schema provenance

| Field | Value |
|---|---|
| Standard | W3C Web of Things Thing Description 1.1 — Thing Model |
| Recommendation | 5 December 2023 |
| Upstream repository | `https://github.com/w3c/wot-thing-description` |
| Upstream tag | `REC1.1` |
| Upstream commit | `7c0b968f403ecdb9594bd882cafbacf544c41fc0` |
| Upstream path | `validation/tm-json-schema-validation.json` |
| Retrieved | 2026-09-05 |
| Bundled path | `priv/w3c/tm-json-schema-validation-1.1.json` |
| Upstream SHA-256 | `d4fecbf6e9713a7c98c85ef8065800b85f72dd690be5016511c72406ed7314f2` |
| Bundled SHA-256 | `3c8dedb2a534d089fdbd7fda8eb05a5b13237a2331f42e2af08cdb4a7af9fc7a` |
| Upstream license | W3C Software and Document License |

Primary sources:

- https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/#thing-model
- https://github.com/w3c/wot-thing-description/tree/REC1.1
- https://www.w3.org/copyright/software-license-2023/

The upstream schema describes itself as version `1.1-09-November-2023` and is
informative. Wotex pins it as a local validation layer and adds explicit
context, bounded-input, and security-reference checks. Validation performs no
network access. The bundled file differs from upstream only by a final
line-feed byte; its parsed JSON value is unchanged.
