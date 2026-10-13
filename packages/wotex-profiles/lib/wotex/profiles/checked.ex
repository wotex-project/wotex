defmodule Wotex.Profiles.Checked do
  @moduledoc "Static checked plans with explicit retained inputs for regeneration; no capture or authority."

  alias Wotex.Profiles.{Compiler, Error, Grammar, Limits}

  @enforce_keys [:data, :inputs]
  defstruct [:data, :inputs]
  @type t :: %__MODULE__{data: map(), inputs: map()}

  @doc "Regenerates the checked plan under the same complete selected limits."
  @spec to_map(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(%__MODULE__{data: data, inputs: inputs} = value, limits) when map_size(value) == 3 do
    with :ok <- Grammar.fields(inputs, ~w(profile closure limits), "/checked"),
         {:ok, limits} <- Limits.new(limits),
         :ok <-
           Grammar.fields(
             data,
             ~w(profile_sha256 closure_sha256 compiler_ref binding channel_plans limits_sha256),
             "/checked"
           ),
         {:ok, _, _} <- Grammar.admit(data, limits),
         true <- inputs["limits"] == limits.data,
         {:ok, checked} <- Compiler.check(inputs["profile"], inputs["closure"], limits),
         true <- data == checked.data do
      {:ok, checked.data}
    else
      false -> Error.refusal(:stale_basis, "/checked")
      error -> error
    end
  end

  def to_map(_, _), do: Error.refusal(:invalid_input, "/checked")
end
