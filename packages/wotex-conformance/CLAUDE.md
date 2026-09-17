# Wotex Conformance Contract

Wotex Conformance is a public, normal Mix library. It owns conformance claims,
vectors, the external target protocol, evidence classification, and reports.
This file governs the `wotex-conformance` package. Repository-wide rules are
in the root `CLAUDE.md`.

## Non-negotiable boundaries

- Use exact W3C Web of Things terminology. `Thing`, `Thing Description`,
  `Property`, `Action`, `Event`, `Form`, and `DataSchema` are canonical terms.
- Refer to an integrating system as a `consumer` or `consumer host`.
- Consumer, company and customer names, consumer-specific rules, customer
  fixtures, and non-public service details stay out of every file. Sibling
  packages are referenced by package name; relative paths inside the
  repository are allowed, absolute machine paths are not.
- Production code may not compile-depend on a tested subject. Subjects are
  exercised only through immutable archives or public interfaces via an
  external adapter.
- Expected values never cross the target protocol boundary.
- This library defines no `Application.start/2`, database, persistence layer,
  background job, network client, global registry, or hidden process tree.
- I/O happens only after an explicit API call. Module loading is inert.
- Do not infer standards support from a module name, fixture presence, or a
  successful unrelated vector.
- A report is evidence for only its exact subject digest, corpus digest, claim,
  vector revision, protocol revision, and environment.
- Public source is not W3C certification or a stable release promise.

## Implementation rules

- Elixir `~> 1.18`, matching `mix.exs`; the repository toolchain in the root
  `.tool-versions` is Elixir 1.20 and Erlang/OTP 29. Minimum-runtime evidence
  and the accepted cohort are reviewed separately under WCF-C06; the Mix
  requirement alone does not prove coverage.
- One module per `.ex` file.
- Use tagged return values and `Wotex.Conformance.Error`; do not raise for
  untrusted data.
- Keep user-controlled strings bounded. Never create atoms from input.
- Canonical JSON is the digest authority. Map keys are strings and sorted by
  their UTF-8 byte representation.
- Reports contain observation digests and bounded diagnostic codes, not raw
  target values, stdout, credentials, endpoints, or exception text.
- External commands use direct executable invocation, never a shell.
- Tests and specifications under `docs/packages/wotex-conformance/` change
  with the contract they prove.

## Required gates

Run `WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-conformance`
before a local commit, then the gate of every dependent package. The gate
verifies the dependency allowlist, the absence of an application callback,
deterministic corpus/report digests, and archive-target isolation through
`bin/check_archive.exs` and `bin/check_application_free.exs`; run
`elixir bin/check_boundary.exs` for the public boundary.
