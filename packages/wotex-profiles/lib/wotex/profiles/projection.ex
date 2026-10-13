defmodule Wotex.Profiles.Projection do
  @moduledoc "Inert capture-bound plans with retained explicit inputs for deterministic regeneration."

  alias Wotex.Profiles.{Compiler, Error, Grammar, Limits}

  @enforce_keys [:data, :inputs]
  defstruct [:data, :inputs]
  @type t :: %__MODULE__{data: map(), inputs: map()}

  @doc "Regenerates static and capture checks; serialized data alone cannot replace its input basis."
  @spec to_map(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(%__MODULE__{data: data, inputs: inputs} = value, limits) when map_size(value) == 3 do
    with :ok <- Grammar.fields(inputs, ~w(profile closure capture limits), "/projection"),
         {:ok, limits} <- Limits.new(limits),
         :ok <-
           Grammar.fields(
             data,
             ~w(profile_sha256 closure_sha256 capture_digest capture_epoch binding compiler_ref channel_plans),
             "/projection"
           ),
         {:ok, _, _} <- Grammar.admit(data, limits),
         true <- inputs["limits"] == limits.data,
         {:ok, projection} <-
           Compiler.compile(inputs["profile"], inputs["closure"], inputs["capture"], limits),
         true <- data == projection.data do
      {:ok, projection.data}
    else
      false -> Error.refusal(:stale_basis, "/projection")
      error -> error
    end
  end

  def to_map(_, _), do: Error.refusal(:invalid_input, "/projection")
end
