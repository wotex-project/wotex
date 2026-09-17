---
name: research-register
description: Write or revise Wotex README files, guides, module documentation, function documentation, types, comments, and specifications in a precise academic technical register that follows Elixir and ExDoc documentation practice.
---

# Wotex research register

Persisted prose states the present contract in precise, declarative language. Apply `unslop` as the final pass.

## Register

- Prefer established terminology from W3C Web of Things, Elixir, Erlang/OTP, and the protocol specification owned by the package.
- Use Thing, Thing Description, Property, Action, Event, Interaction Affordance, DataSchema, Form, ConsumedThing, and ExposedThing only with their W3C meanings.
- Expand an uncommon acronym at first use. Preserve the owner’s spelling for standards and external projects.
- Distinguish a cited standard requirement, a package interpretation, and an implementation choice.
- Name the exact revision and status behind a standards claim. Label drafts as drafts.
- Describe implemented behavior in the present tense. Mark planned behavior and unexecuted evidence explicitly.
- Use complete sentences, one principal claim per sentence where practical. Avoid marketing language and invented names.
- Keep examples consumer-neutral and use reserved domains, reserved URNs, and synthetic values. Sibling packages are named by package name; relative paths inside this repository are allowed, absolute machine paths are not.

## README structure

A package README (`packages/<name>/README.md`) begins with its name, a concise factual description, and the standard package badges. It then provides installation, a minimal working example, the package’s semantic or execution model, error and limit behavior, explicit ownership boundaries, standards status, and development verification as applicable. Navigation and tables must aid retrieval rather than decorate the page.

## API documentation

Elixir documentation is a public contract.

- Keep the first paragraph concise because ExDoc uses it as a summary.
- Reference modules by full name and enclose them in backticks.
- Reference functions with name and arity, types with `t:`, and callbacks with `c:`.
- Start sections with `##`; the generated module or function title owns the first-level heading.
- Put examples under `## Examples`. Prefer doctests when the example is deterministic, isolated, and stable.
- Place `@doc` before the first clause of a multi-clause function.
- Use documentation metadata such as `:since` only when the package can support the claim.

A production `@moduledoc` must be substantive. A one-line restatement of the module name is not acceptable. Explain the module’s purpose, when a consumer uses it, the important value or execution semantics, relevant errors or limits, and its relationship to adjacent modules. Add examples when they clarify correct use. Do not lengthen a document with repetition.

Every checked-in production module has substantive `@moduledoc` text grounded in its current behavior, including implementation helpers and protocol implementations. Do not use `@moduledoc false` in `lib/`. Explain an internal module's role and boundaries, keep its internal status explicit in the prose, describe internal ownership without implying a stable consumer API, and direct consumers to the supported entry point. Every test and test-support module uses `@moduledoc false` followed by exactly one blank line.

Executable examples in module documentation use real `iex>` prompts and are exercised by a matching `doctest` declaration in the test suite. Configuration, network, and external-resource sketches that require caller-owned resources are labelled as sketches and covered through the corresponding executable fixtures. Do not add vacuous doctest declarations for prose or code fences, and do not present a doctest declaration with no executable examples as coverage.

## Review

Before handoff:

- confirm the concise first paragraph renders as a useful ExDoc summary;
- resolve broken module, function, callback, and type references through `mix docs` run inside the package;
- remove unsupported compatibility, conformance, certification, stability, and completion claims;
- verify examples against the current API and package boundary;
- run the package documentation gate and the `unslop` pass.
