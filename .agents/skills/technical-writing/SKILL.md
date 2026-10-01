---
name: technical-writing
description: Write or revise README prose, guides, specifications, API docs and comments with accurate contracts and working examples. Use for substantial persisted text changes and the final prose review; exclude generated release metadata.
user-invocable: false
---

# Write technical guidance

Input: the intended reader, changed behavior, current API and owning sources.
Output: concise prose and examples that match that behavior and render correctly.

State what the reader needs to know first. Use concrete operations and
established protocol terms. Distinguish a standard requirement, package
interpretation, implementation choice and planned behavior. Remove promotional
language, filler and repeated conclusions without changing normative strength,
identifiers, values or evidence qualifications.

Keep README installation and minimal examples usable. Explain ownership,
limits and failure behavior where a consumer needs them; preserve the existing
package structure rather than imposing sections on every document.

For Elixir API documentation:
- Make the first paragraph a useful ExDoc summary.
- Refer to modules by full name, functions by name and arity, types with
  `t:` and callbacks with `c:`; start body sections with `##`.
- Put `@doc` before the first clause of a multi-clause function.
- Document internal roles without implying a supported consumer API.
- Use real `iex>` prompts for deterministic examples and exercise them with
  the relevant doctest. Label resource-dependent sketches as such; a doctest
  declaration without executable examples proves nothing.
- Use metadata such as `:since` only when the history supports it.

Check examples against the actual API, not module names or text matches.
Use `mix docs.pkg <name>` for changed ExDoc references and
`mix docs.check` for repository Markdown links when those checks are relevant.
Read the final text for accuracy and clarity. Report any example or rendering
check that was not executed.
