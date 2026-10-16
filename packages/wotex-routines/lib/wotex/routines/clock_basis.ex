defmodule Wotex.Routines.ClockBasis do
  @moduledoc false

  alias Wotex.Routines.Error

  @doc false
  @spec format(map()) :: String.t()
  def format(time), do: Map.get(time, "format", "wotex.routines.time@1")

  @doc false
  @spec utc_generation(map()) :: String.t() | nil
  def utc_generation(%{"format" => "wotex.routines.time@2"} = time),
    do: time["utc_generation"]

  def utc_generation(time), do: time["clock_generation"]

  @doc false
  @spec utc_projection(map()) :: {String.t(), String.t() | nil}
  def utc_projection(time), do: {format(time), utc_generation(time)}

  @doc false
  @spec require_utc(map()) :: :ok | {:error, Error.t()}
  def require_utc(time) do
    if utc_generation(time) == nil,
      do: Error.refusal(:missing_utc_basis),
      else: :ok
  end

  @doc false
  @spec bind_format(map(), map()) :: map()
  def bind_format(data, %{"format" => "wotex.routines.time@2"}),
    do: Map.put(data, "time_format", "wotex.routines.time@2")

  def bind_format(data, _), do: data
end
