# Decision: exercise subjects through an external target protocol

## Status

Accepted.

## Context

A conformance package that compiles every tested subject reverses the intended
dependency graph. It also lets subject code share application configuration,
processes, modules, and fixtures with the runner, weakening the evidence that an
immutable package works independently.

## Decision

Production code tests subjects through a versioned JSON protocol implemented by
a separate executable. The runner verifies an immutable subject archive before
invocation. One fresh process handles one vector.

Expected values remain exclusively inside the verified corpus. The external
target receives only subject identity, claim, vector identity/input, and bounded
execution context. It returns an observation or an unsupported outcome; it
cannot return pass or fail.

The observation shape itself is normalized per operation, and each vector
declares the projection its observation reports; see decision 0003.

## Consequences

- Subject packages are absent from production dependencies.
- Adapters can address archives or public APIs without changing the runner.
- Process startup, timeout, output bounds, and protocol failures are visible as
  infrastructure errors.
- The consumer must provide operating-system isolation for untrusted code.
- Adapter authoring is additional work, but it makes normalization and claim
  boundaries explicit.
