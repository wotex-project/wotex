Code.require_file("support/observations.exs", __DIR__)

alias Wotex.Conformance.Bench.Observations
alias Wotex.Conformance.{Canonical, Observation, Pointer}

operation = "thing_description.parse"

inputs =
  Enum.map(Observations.sizes(), fn {label, count} -> {label, Observations.sample(count)} end)

Benchee.run(
  %{
    "validate vector input" => fn %{input: input} ->
      {:ok, _} = Observation.validate_input(operation, input)
    end,
    "validate accepted observation" => fn %{accepted: accepted} ->
      {:ok, _} = Observation.validate(operation, accepted)
    end,
    "validate rejected observation" => fn %{rejected: rejected} ->
      {:ok, _} = Observation.validate(operation, rejected)
    end,
    "digest accepted observation" => fn %{accepted: accepted} ->
      {:ok, _} = Canonical.digest(accepted)
    end,
    "encode projection pointers" => fn %{segments: segments, pointers: pointers} ->
      ^pointers = Enum.map(segments, &Pointer.encode/1)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/observation.md",
     title: "# Normalized observations and pointer projections",
     description: """
     `Wotex.Conformance.Observation` over a `thing_description.parse` vector
     whose input document declares 64 Properties and whose projection names
     one, eight or 64 of them as RFC 6901 JSON Pointers. The accepted
     observation maps each pointer to its Property; the rejected observation
     carries one sorted error per pointer. The digest job is the canonical
     SHA-256 digest the runner compares with the expectation, and the pointer
     job encodes the projection with `Wotex.Conformance.Pointer.encode/1`.
     """}
  ]
)
