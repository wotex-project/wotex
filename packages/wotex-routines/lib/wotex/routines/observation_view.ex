defmodule Wotex.Routines.ObservationView do
  @moduledoc false

  alias Wotex.Routines.{Limits, Unit}

  @doc false
  @spec values(map(), map(), map(), Limits.t()) :: map()
  def values(program, snapshot, time, limits) do
    bases = Map.new(program["context"]["bases"], &{&1["id"], &1})

    Map.new(program["context"]["bindings"], fn {name, binding} ->
      basis = bases[binding["basis"]["id"]]
      fact = snapshot["facts"][name]
      expected = snapshot["binding_bases"][name]
      {name, qualify(fact, binding, basis, expected, time, limits)}
    end)
  end

  defp qualify(nil, _, _, _, _, _), do: :unknown

  defp qualify(fact, binding, basis, expected, time, limits) do
    if identity?(fact, binding, basis, expected) and freshness?(fact, basis, expected, time) do
      value(fact, basis["value"], limits)
    else
      :unknown
    end
  end

  defp identity?(fact, binding, basis, expected) do
    affordance = basis["affordance"]
    evidence = basis["evidence"]

    fact["quality"] == "usable" and fact["replay"] == "fresh" and
      fact["continuity"] != "lost" and
      (evidence["continuity"] == "snapshot" or fact["continuity"] == "continuous") and
      fact["thing_id"] == binding["thing_id"] and
      fact["affordance_type"] == affordance["type"] and
      fact["affordance_name"] == affordance["name"] and
      fact["profile_digest"] == expected["profile_digest"] and
      fact["source_id"] == expected["source_id"] and
      fact["source_epoch"] == expected["source_epoch"] and
      fact["source_class"] in evidence["sources"]
  end

  defp freshness?(fact, basis, expected, time) do
    freshness = basis["evidence"]["freshness_ms"]
    elapsed = time["elapsed_ms"]

    receipt =
      fact["receipt_epoch"] == time["epoch"] and elapsed >= fact["receipt_ms"] and
        elapsed - fact["receipt_ms"] <= freshness and elapsed < fact["expires_ms"]

    receipt and
      (not basis["evidence"]["require_source_time"] or source_age?(fact, expected, time, freshness))
  end

  defp source_age?(fact, expected, time, freshness) do
    if fact["source_time_trust"] == "trusted" and fact["source_time_basis"] != nil and
         fact["source_time_basis"] == expected["source_time_basis"] and
         time["utc_low_ms"] != nil and time["utc_high_ms"] != nil do
      {:ok, instant, _} = DateTime.from_iso8601(fact["source_time"])
      center = DateTime.to_unix(instant, :millisecond)
      source_low = center - fact["source_uncertainty_ms"]
      source_high = center + fact["source_uncertainty_ms"]
      source_high <= time["utc_low_ms"] and time["utc_high_ms"] - source_low <= freshness
    else
      false
    end
  end

  defp value(%{"value" => value}, %{"type" => "boolean"}, _) when is_boolean(value),
    do: {:known, value}

  defp value(%{"value" => value}, %{"type" => "enum", "enum" => choices}, _) do
    if value in choices, do: {:known, value}, else: :unknown
  end

  defp value(%{"value" => value, "unit" => unit}, %{"type" => "integer", "unit" => target}, limits) do
    case Unit.convert(value, unit, target, limits) do
      {:ok, value} -> {:known, value}
      _ -> :unknown
    end
  end

  defp value(_, _, _), do: :unknown
end
