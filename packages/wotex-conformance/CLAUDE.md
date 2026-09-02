# Repository contract

Wotex Conformance is a public, normal Mix library. It owns conformance claims,
vectors, the external target protocol, evidence classification, and reports.

## Non-negotiable boundaries

- Use exact W3C Web of Things terminology. `Thing`, `Thing Description`,
  `Property`, `Action`, `Event`, `Form`, and `DataSchema` are canonical terms.
- Refer to an integrating system as a `consumer` or `consumer host`.
- Keep consumer names, consumer namespaces, consumer-specific rules, customer
  fixtures, internal paths, and non-public service details out of every file.
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

- Elixir `~> 1.19`; CI uses Erlang/OTP 28.5.
- One module per `.ex` file.
- Use tagged return values and `Wotex.Conformance.Error`; do not raise for
  untrusted data.
- Keep user-controlled strings bounded. Never create atoms from input.
- Canonical JSON is the digest authority. Map keys are strings and sorted by
  their UTF-8 byte representation.
- Reports contain observation digests and bounded diagnostic codes, not raw
  target values, stdout, credentials, endpoints, or exception text.
- External commands use direct executable invocation, never a shell.
- Tests and specifications change with the contract they prove.
- Commits use a conventional lowercase subject without task/spec identifiers,
  attribution trailers, or generated-author language.

## Required gates

Run `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix test`, `mix docs`, and `mix hex.build`. Verify the dependency allowlist,
the absence of an application callback, deterministic corpus/report digests,
and archive-target isolation before handoff.
