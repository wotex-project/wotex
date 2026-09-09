defmodule Wotex.Lab.Formal.Abstraction do
  @moduledoc """
  The explicit abstraction between smart-room state and `thermal-control-v1`.

  A concrete room is a map of measured and policy values; `room/2` maps it to
  the finite model terms and reports what the discretization loses:

  * temperature in degrees Celsius becomes a band: below 19.0 is `cold`, at
    or above 24.0 is `hot`, otherwise `comfort`; the exact reading is lost;
  * heater and cooler are `on` or `off`;
  * power above the budget in watts is `over`, otherwise `within`;
  * the decision slot is `noDecision`, `granted(action, age)` or
    `dispatched(action, age)` where the age is the observation age at grant or
    dispatch time in whole seconds, rounded down and capped at `max_age`;
  * the observation age in whole seconds is capped the same way;
  * grants and effects are counts capped at `max_grants` and `max_grants + 1`.

  `from_term/1` reads a `room(...)` term printed by Maude back into the same
  abstract map so traces and replays compare like with like.
  """

  alias Wotex.Lab.Error

  @cold_below 19.0
  @hot_from 24.0
  @default_bounds %{max_age: 3, max_grants: 2}

  @type action :: :heat | :cool
  @type decision ::
          :no_decision
          | {:granted, action(), non_neg_integer()}
          | {:dispatched, action(), non_neg_integer()}

  @type t :: %{
          band: :cold | :comfort | :hot,
          heater: :on | :off,
          cooler: :on | :off,
          energy: :within | :over,
          decision: decision(),
          age: non_neg_integer(),
          grants: non_neg_integer(),
          effects: non_neg_integer()
        }

  @doc "The initial abstract room, matching the model's `init`."
  @spec init() :: t()
  def init,
    do: %{
      band: :comfort,
      heater: :off,
      cooler: :off,
      energy: :within,
      decision: :no_decision,
      age: 0,
      grants: 0,
      effects: 0
    }

  @doc "Abstracts a concrete room; returns the abstract state and the information lost."
  @spec room(map(), map()) :: {:ok, t(), map()} | {:error, Error.t()}
  def room(concrete, bounds \\ @default_bounds)

  def room(concrete, %{max_age: max_age, max_grants: max_grants}) when is_map(concrete) do
    with :ok <- concrete(concrete),
         {:ok, abstract_decision, lost_decision} <- decision(concrete.decision, max_age) do
      age = min(div(concrete.age_ms, 1_000), max_age)

      abstract = %{
        band: band(concrete.temperature),
        heater: concrete.heater,
        cooler: concrete.cooler,
        energy: if(concrete.power > concrete.budget, do: :over, else: :within),
        decision: abstract_decision,
        age: age,
        grants: min(concrete.grants, max_grants),
        effects: min(concrete.effects, max_grants + 1)
      }

      lost = %{
        temperature: concrete.temperature,
        power: concrete.power,
        budget: concrete.budget,
        age_ms: concrete.age_ms,
        age_rounding: concrete.age_ms - age * 1_000,
        grants_capped: concrete.grants > max_grants,
        effects_capped: concrete.effects > max_grants + 1,
        decision: lost_decision
      }

      {:ok, abstract, lost}
    end
  end

  def room(_, _), do: {:error, invalid()}

  @fields [:temperature, :heater, :cooler, :power, :budget, :decision, :age_ms, :grants, :effects]

  defp concrete(map) do
    with true <- Enum.all?(@fields, &Map.has_key?(map, &1)),
         true <- is_number(map.temperature) and is_number(map.power) and is_number(map.budget),
         true <- map.heater in [:on, :off] and map.cooler in [:on, :off],
         true <- count?(map.age_ms) and count?(map.grants) and count?(map.effects) do
      :ok
    else
      false -> {:error, invalid()}
    end
  end

  defp count?(value), do: is_integer(value) and value >= 0

  defp invalid,
    do:
      Error.new(
        :invalid_concrete_room,
        :abstraction,
        "concrete room is missing fields or has invalid values"
      )

  @doc "Parses a `room(...)` term as printed by Maude."
  @spec from_term(String.t()) :: {:ok, t()} | {:error, Error.t()}
  def from_term(term) when is_binary(term) do
    regex =
      ~r/\Aroom\((cold|comfort|hot), (on|off), (on|off), (within|over), (noDecision|granted\((heat|cool), (\d+)\)|dispatched\((heat|cool), (\d+)\)), (\d+), (\d+), (\d+)\)\z/

    case Regex.run(regex, String.trim(term)) do
      [_, band, heater, cooler, energy, decision, ga, gage, da, dage, age, grants, effects] ->
        {:ok,
         %{
           band: closed(band, %{"cold" => :cold, "comfort" => :comfort, "hot" => :hot}),
           heater: closed(heater, %{"on" => :on, "off" => :off}),
           cooler: closed(cooler, %{"on" => :on, "off" => :off}),
           energy: closed(energy, %{"within" => :within, "over" => :over}),
           decision: decision_from(decision, ga, gage, da, dage),
           age: String.to_integer(age),
           grants: String.to_integer(grants),
           effects: String.to_integer(effects)
         }}

      _ ->
        {:error,
         Error.new(:invalid_term, :abstraction, "term is not a room state",
           details: %{term: String.slice(term, 0, 128)}
         )}
    end
  end

  defp band(temperature) when temperature < @cold_below, do: :cold
  defp band(temperature) when temperature >= @hot_from, do: :hot
  defp band(_), do: :comfort

  defp decision(:no_decision, _), do: {:ok, :no_decision, nil}

  defp decision({status, action, ms}, max_age)
       when status in [:granted, :dispatched] and action in [:heat, :cool] and is_integer(ms) and
              ms >= 0,
       do: {:ok, {status, action, min(div(ms, 1_000), max_age)}, %{age_ms: ms}}

  defp decision(_, _),
    do:
      {:error,
       Error.new(
         :invalid_concrete_room,
         :abstraction,
         "decision must be :no_decision or {status, action, age_ms}"
       )}

  defp closed(value, table), do: Map.fetch!(table, value)

  defp decision_from("noDecision", _, _, _, _), do: :no_decision

  defp decision_from("granted" <> _, action, age, _, _),
    do: {:granted, closed(action, %{"heat" => :heat, "cool" => :cool}), String.to_integer(age)}

  defp decision_from("dispatched" <> _, _, _, action, age),
    do: {:dispatched, closed(action, %{"heat" => :heat, "cool" => :cool}), String.to_integer(age)}
end
