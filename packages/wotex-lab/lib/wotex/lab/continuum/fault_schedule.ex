defmodule Wotex.Lab.Continuum.FaultSchedule do
  @moduledoc """
  A versioned, deterministic fault schedule for the in-memory channel.

  Faults are keyed by the channel's send sequence so a schedule is a replayable
  input with an expected outcome rather than a random injector:

  * `drop` sequences are never delivered and end as `failed` deliveries;
  * `duplicate` sequences are delivered twice under the same delivery id;
  * `hold` maps a sequence to a later sequence; the held item is delivered
    only after that later item has been sent, which reorders the two.

  Disconnection is not scheduled here because it is an explicit host event on
  the channel (`disconnect/1` and `reconnect/1`).
  """

  alias Wotex.Lab.Error

  @version "1.0.0"

  @type t :: %__MODULE__{
          version: String.t(),
          drop: MapSet.t(pos_integer()),
          duplicate: MapSet.t(pos_integer()),
          hold: %{pos_integer() => pos_integer()}
        }

  defstruct version: @version, drop: MapSet.new(), duplicate: MapSet.new(), hold: %{}

  @doc "Builds a schedule; `drop:` and `duplicate:` are sequence lists, `hold:` maps a sequence to the sequence that releases it."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts \\ []) when is_list(opts) do
    drop = Keyword.get(opts, :drop, [])
    duplicate = Keyword.get(opts, :duplicate, [])
    hold = Keyword.get(opts, :hold, %{})

    if sequences?(drop) and sequences?(duplicate) and holds?(hold) do
      {:ok, %__MODULE__{drop: MapSet.new(drop), duplicate: MapSet.new(duplicate), hold: hold}}
    else
      {:error,
       Error.new(
         :invalid_fault_schedule,
         :construction,
         "fault schedule sequences must be positive integers"
       )}
    end
  end

  @doc "Returns the schedule version recorded with channel evidence."
  @spec version() :: String.t()
  def version, do: @version

  defp sequences?(values), do: is_list(values) and Enum.all?(values, &(is_integer(&1) and &1 > 0))

  defp holds?(hold),
    do:
      is_map(hold) and
        Enum.all?(hold, fn {held, until} ->
          is_integer(held) and is_integer(until) and until > held
        end)
end
