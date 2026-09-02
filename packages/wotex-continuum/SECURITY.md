# Security Policy

## Supported versions

Until a stable release, only the latest published pre-1.0 release receives
security fixes.

## Reporting

Report suspected vulnerabilities privately to `hello@wotex.io`. Include the
affected version, minimal reproduction, impact, and any known mitigation. Do
not open a public issue before maintainers coordinate disclosure.

## Boundary

The library handles untrusted JSON but performs no network, filesystem,
credential, process, or database operation. Its decoder enforces byte, nesting,
collection-size, and string-size limits supplied by the consumer. Defaults are
conservative and can be tightened.

Consumer hosts remain responsible for:

- authenticating and authorizing principals;
- validating Thing Description and DataSchema meaning through the Wotex core;
- preventing Action replay and enforcing idempotency;
- resolving evidence URIs under an allowlist;
- redacting sensitive values before logging;
- bounding persistence and delivery queues; and
- treating decoded values as proposals, never authority.

An Action intent or result is data only. Decoding it cannot authorize or
execute an Action.
