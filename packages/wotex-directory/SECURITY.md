# Security policy

## Supported versions

Before the first stable release, the current development line receives security
updates. After stable release, the latest stable minor line and explicitly
listed long-lived lines are supported.

## Reporting

Report suspected vulnerabilities privately to hello@wotex.io. Include affected
versions, reproduction conditions, impact, and a minimal proof when safe. Do
not open a public issue before coordinated disclosure.

The maintainers will acknowledge the report, assess affected versions, prepare
a fix and tests, and coordinate disclosure. No response-time promise is made.

## Boundary

The consumer is responsible for authentication, authorization policy,
repository isolation, transport security, credential handling, deployment, and
operational monitoring. This library guarantees only its documented port order,
bounded operations, validation-before-write behavior, and deterministic errors.
