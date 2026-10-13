defmodule Wotex.Profiles.AuthoringLimits do
  @moduledoc "Complete explicit reader, candidate, diagnostic and work budgets for profile authoring."

  alias Wotex.Profiles.{Error, Grammar, Limits}

  @ceilings %{
    "max_bundle_bytes" => 1_048_576,
    "max_diagnostics" => 256,
    "max_report_bytes" => 65_536,
    "max_check_steps" => 1_000_000
  }
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Revalidates all selections; no missing or ambient default is supplied."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{data: data} = value) when map_size(value) == 2, do: new(data)

  def new(data) do
    with :ok <- Grammar.fields(data, ["reader" | Map.keys(@ceilings)], "/limits"),
         {:ok, reader} <- Limits.new(data["reader"]),
         true <-
           Enum.all?(@ceilings, fn {key, ceiling} ->
             is_integer(data[key]) and data[key] in 1..ceiling
           end) do
      {:ok, %__MODULE__{data: Map.put(data, "reader", reader.data)}}
    else
      false -> Error.refusal(:invalid_input, "/limits")
      error -> error
    end
  end

  @doc "Returns the checked complete map."
  @spec to_map(term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value) do
    with {:ok, value} <- new(value), do: {:ok, value.data}
  end
end
