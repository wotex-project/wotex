defmodule Wotex.Lab.Formal.Result do
  @moduledoc """
  The result of one bounded verification.

  `status` is one of `:counterexample`, `:verified_in_model`, `:inconclusive`,
  `:timeout`, `:unsupported` or `:error`. A bounded search with no solution is
  `:inconclusive` unless `exhaustion.basis` is `:complete_search`, which the
  profile establishes only when an unbounded-depth search of the declared
  finite model terminated within the deadline. `verified_in_model` speaks
  about the recorded model, abstraction and inputs only; it is never an
  authorization, a physical claim, a probability or a conformance result.
  Every result carries the digests, engine versions, bounds and explored
  counts that make it attributable, and `to_map/1` is its evidence form.
  """

  @type status ::
          :counterexample | :verified_in_model | :inconclusive | :timeout | :unsupported | :error

  @type t :: %__MODULE__{
          status: status(),
          property: atom(),
          variant: atom(),
          model: %{id: atom(), digest: String.t(), module: String.t()},
          abstraction_digest: String.t(),
          input_digest: String.t(),
          query_digest: String.t(),
          engine: %{maude: String.t(), ex_maude: String.t()},
          bounds: %{
            max_depth: pos_integer(),
            max_solutions: pos_integer(),
            deadline_ms: pos_integer(),
            max_output_bytes: pos_integer()
          },
          explored: %{states: non_neg_integer(), rewrites: non_neg_integer()} | nil,
          exhaustion: %{
            basis: :complete_search | :depth_bound | :none,
            states: non_neg_integer() | nil
          },
          counterexample: [map()] | nil,
          error: map() | nil
        }

  @enforce_keys [
    :status,
    :property,
    :variant,
    :model,
    :abstraction_digest,
    :input_digest,
    :query_digest,
    :engine,
    :bounds
  ]
  defstruct [
    :status,
    :property,
    :variant,
    :model,
    :abstraction_digest,
    :input_digest,
    :query_digest,
    :engine,
    :bounds,
    explored: nil,
    exhaustion: %{basis: :none, states: nil},
    counterexample: nil,
    error: nil
  ]

  @doc "The evidence form of a result, with string keys and plain values."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      "status" => Atom.to_string(result.status),
      "property" => Atom.to_string(result.property),
      "variant" => Atom.to_string(result.variant),
      "model" => %{
        "id" => Atom.to_string(result.model.id),
        "digest" => result.model.digest,
        "module" => result.model.module
      },
      "abstraction_digest" => result.abstraction_digest,
      "input_digest" => result.input_digest,
      "query_digest" => result.query_digest,
      "engine" => %{"maude" => result.engine.maude, "ex_maude" => result.engine.ex_maude},
      "bounds" => Map.new(result.bounds, fn {key, value} -> {Atom.to_string(key), value} end),
      "explored" =>
        result.explored &&
          Map.new(result.explored, fn {key, value} -> {Atom.to_string(key), value} end),
      "exhaustion" => %{
        "basis" => Atom.to_string(result.exhaustion.basis),
        "states" => result.exhaustion.states
      },
      "counterexample" =>
        result.counterexample &&
          Enum.map(result.counterexample, fn step ->
            %{"state" => step.state, "rule" => step.rule, "term" => step.term}
          end),
      "error" =>
        result.error &&
          Map.new(result.error, fn {key, value} -> {Atom.to_string(key), plain(value)} end)
    }
  end

  defp plain(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp plain(value) when is_map(value),
    do: Map.new(value, fn {key, inner} -> {to_string(key), plain(inner)} end)

  defp plain(value), do: value
end
