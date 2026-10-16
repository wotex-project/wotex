defmodule Wotex.Routines.TransitionEdge do
  @moduledoc false

  alias Wotex.Routines.{ClockBasis, TransitionChecks, Validation}

  @doc false
  @spec verify(map(), map() | nil) ::
          {:ok, boolean()} | {:error, Wotex.Routines.Error.t()}
  def verify(%{event: %{"kind" => "fact"}} = c, claimed) do
    trigger = c.program["ir"]["trigger"]
    fact = c.snapshot["facts"][trigger["binding"]]

    with :ok <- TransitionChecks.condition(is_map(claimed), "/edge"),
         :ok <-
           TransitionChecks.condition(
             trigger["kind"] == "edge" and c.event["binding"] == trigger["binding"] and
               is_map(fact) and c.event["fact_id"] == fact["id"],
             "/event/fact_id"
           ),
         {:ok, digest} <- Validation.hash(fact, c.limits) do
      relation(c, claimed, fact, digest, trigger)
    end
  end

  def verify(c, claimed) do
    with :ok <- TransitionChecks.equal(claimed, c.prior["edge"], "/edge"), do: {:ok, true}
  end

  defp relation(c, claimed, fact, digest, trigger) do
    old = c.prior["edge"]
    initial = template(c, trigger["binding"])
    identity = ~w(format binding_basis epoch clock_generation)
    reset = old == nil or Map.take(old, identity) != Map.take(initial, identity)
    retained = if reset, do: initial, else: old
    qualified = fact["continuity"] == "continuous" and c.values[trigger["binding"]] != :unknown

    same = same_sample?(reset, old, fact)

    cond do
      not qualified ->
        conclude(claimed, retained, %{"baseline" => nil, "candidate_since_ms" => nil}, false)

      same and old["last_fact_digest"] != digest ->
        TransitionChecks.refuse("/edge/last_fact_digest")

      regressed_time?(reset, old, c.time) ->
        conclude(claimed, old, %{"baseline" => nil, "candidate_since_ms" => nil}, false)

      same ->
        conclude(claimed, old, %{"last_elapsed_ms" => c.time["elapsed_ms"]}, false)

      regressed_sample?(reset, old, fact) ->
        conclude(
          claimed,
          old,
          %{
            "baseline" => nil,
            "candidate_since_ms" => nil,
            "last_elapsed_ms" => c.time["elapsed_ms"]
          },
          false
        )

      true ->
        sample(c, claimed, retained, fact, digest, trigger)
    end
  end

  defp same_sample?(true, _, _), do: false

  defp same_sample?(false, old, fact),
    do: old["last_fact_id"] == fact["id"] or old["last_sequence"] == fact["sequence"]

  defp regressed_time?(true, _, _), do: false
  defp regressed_time?(false, old, time), do: time["elapsed_ms"] < old["last_elapsed_ms"]
  defp regressed_sample?(true, _, _), do: false
  defp regressed_sample?(false, %{"last_sequence" => nil}, _), do: false

  defp regressed_sample?(false, old, fact),
    do: fact["sequence"] <= old["last_sequence"] or fact["receipt_ms"] < old["last_receipt_ms"]

  defp sample(c, claimed, retained, fact, digest, trigger) do
    remembered = %{
      "last_elapsed_ms" => c.time["elapsed_ms"],
      "last_receipt_ms" => fact["receipt_ms"],
      "last_sequence" => fact["sequence"],
      "last_fact_id" => fact["id"],
      "last_fact_digest" => digest
    }

    {:known, value} = c.values[trigger["binding"]]
    active = active(trigger, value, retained)

    cond do
      retained["baseline"] == nil ->
        conclude(claimed, retained, Map.put(remembered, "baseline", active), false)

      active in [nil, false] ->
        conclude(
          claimed,
          retained,
          Map.merge(remembered, %{"baseline" => active, "candidate_since_ms" => nil}),
          false
        )

      retained["baseline"] == true ->
        conclude(claimed, retained, remembered, false)

      true ->
        candidate(c, claimed, retained, remembered, trigger)
    end
  end

  defp candidate(c, claimed, retained, remembered, trigger) do
    now = c.time["elapsed_ms"]
    since = retained["candidate_since_ms"] || now

    cond do
      now < retained["cooldown_until_ms"] ->
        conclude(
          claimed,
          retained,
          Map.merge(remembered, %{"baseline" => true, "candidate_since_ms" => nil}),
          false
        )

      now - since < trigger["debounce_ms"] ->
        conclude(claimed, retained, Map.put(remembered, "candidate_since_ms", since), false)

      true ->
        until = now + trigger["cooldown_ms"]

        with :ok <- Validation.integer(until, c.limits, "/edge/cooldown_until_ms", 0) do
          conclude(
            claimed,
            retained,
            Map.merge(remembered, %{
              "baseline" => true,
              "candidate_since_ms" => nil,
              "cooldown_until_ms" => until,
              "last_original" => c.event["original"]
            }),
            true
          )
        end
    end
  end

  defp active(%{"hysteresis" => nil, "direction" => direction}, value, _),
    do: if(direction == "rising", do: value, else: not value)

  defp active(trigger, value, old) do
    band = trigger["hysteresis"]

    cond do
      trigger["direction"] == "rising" and value >= band["enter"] -> true
      trigger["direction"] == "rising" and value <= band["exit"] -> false
      trigger["direction"] == "falling" and value <= band["enter"] -> true
      trigger["direction"] == "falling" and value >= band["exit"] -> false
      old["candidate_since_ms"] != nil -> true
      true -> old["baseline"]
    end
  end

  defp conclude(claimed, before, changed, eligible) do
    keys = Map.keys(changed)

    with :ok <- TransitionChecks.equal(Map.drop(claimed, keys), Map.drop(before, keys), "/edge"),
         :ok <- TransitionChecks.fields(claimed, changed, "/edge") do
      {:ok, eligible}
    end
  end

  defp template(c, name) do
    data = %{
      "format" =>
        if(ClockBasis.format(c.time) == "wotex.routines.time@2",
          do: "wotex.routines.edge@2",
          else: "wotex.routines.edge@1"
        ),
      "program_digest" => c.program["ir_digest"],
      "binding" => name,
      "binding_basis" => c.snapshot["binding_bases"][name],
      "epoch" => c.time["epoch"],
      "clock_generation" => c.time["clock_generation"],
      "last_elapsed_ms" => c.time["elapsed_ms"],
      "last_receipt_ms" => nil,
      "last_sequence" => nil,
      "last_fact_id" => nil,
      "last_fact_digest" => nil,
      "baseline" => nil,
      "candidate_since_ms" => nil,
      "cooldown_until_ms" => 0,
      "last_original" => nil
    }

    if ClockBasis.format(c.time) == "wotex.routines.time@2",
      do: Map.put(data, "time_format", "wotex.routines.time@2"),
      else: data
  end
end
