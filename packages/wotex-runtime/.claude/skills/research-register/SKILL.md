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
- Keep examples consumer-neutral and use reserved domains, reserved URNs, and synthetic values.

## README structure

A package README begins with its name, a concise factual description, and the standard package badges. It then provides installation, a minimal working example, the package’s semantic or execution model, error and limit behavior, explicit ownership boundaries, standards status, and development verification as applicable. Navigation and tables must aid retrieval rather than decorate the page.

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

Internal production modules may use `@moduledoc false` when they are intentionally excluded from the public API. Every test and test-support module uses `@moduledoc false` followed by exactly one blank line.

## Review

Before handoff:

- confirm the concise first paragraph renders as a useful ExDoc summary;
- resolve broken module, function, callback, and type references through `mix docs`;
- remove unsupported compatibility, conformance, certification, stability, and completion claims;
- verify examples against the current API and package boundary;
- run the repository documentation gate and the `unslop` pass.
