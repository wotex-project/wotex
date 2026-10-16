defmodule Wotex.Routines.TransitionObservation do
  @moduledoc false

  alias Wotex.Routines.{Limits, Unit}

  # These relations consume structurally checked inputs. They deliberately do
  # not call the forward observation or predicate evaluator.
  @doc false
  @spec values(map(), map(), map(), Limits.t()) :: map()
  def values(program, snapshot, time, limits) do
    installed = Map.new(program["context"]["bases"], &{&1["id"], &1})

    Map.new(program["context"]["bindings"], fn {name, binding} ->
      basis = installed[binding["basis"]["id"]]
      fact = snapshot["facts"][name]
      expected = snapshot["binding_bases"][name]

      value =
        if usable?(fact, binding, basis, expected, time),
          do: typed(fact, basis["value"], limits),
          else: :unknown

      {name, value}
    end)
  end

  @doc false
  @spec predicate(list(), map()) :: boolean() | String.t()
  def predicate(code, values) do
    [truth] = Enum.reduce(code, [], &instruction(&1, &2, values))
    truth
  end

  defp usable?(nil, _, _, _, _), do: false

  defp usable?(fact, binding, basis, expected, time) do
    contract = basis["evidence"]
    affordance = basis["affordance"]

    Enum.all?([
      fact["quality"] == "usable",
      fact["replay"] == "fresh",
      fact["continuity"] != "lost",
      contract["continuity"] == "snapshot" or fact["continuity"] == "continuous",
      fact["thing_id"] == binding["thing_id"],
      fact["affordance_type"] == affordance["type"],
      fact["affordance_name"] == affordance["name"],
      fact["profile_digest"] == expected["profile_digest"],
      fact["source_id"] == expected["source_id"],
      fact["source_epoch"] == expected["source_epoch"],
      fact["source_class"] in contract["sources"],
      external?(fact, expected),
      receipt?(fact, time, contract["freshness_ms"]),
      source?(fact, expected, time, contract)
    ])
  end

  defp external?(fact, %{"format" => "wotex.routines.external-binding@1"} = expected) do
    mapping = expected["input_mapping"]

    fact["source_class"] == mapping["observation"]["source_class"] and
      fact["source_time_basis"] == expected["source_time_basis"] and
      fact["receipt_epoch"] == mapping["receipt_clock"]["target_epoch"]
  end

  defp external?(_, _), do: true

  defp receipt?(fact, time, freshness) do
    n = time["elapsed_ms"]

    fact["receipt_epoch"] == time["epoch"] and n >= fact["receipt_ms"] and
      n <= fact["receipt_ms"] + freshness and n < fact["expires_ms"]
  end

  defp source?(_, _, _, %{"require_source_time" => false}), do: true

  defp source?(fact, expected, time, contract) do
    if fact["source_time_trust"] == "trusted" and fact["source_time_basis"] != nil and
         fact["source_time_basis"] == expected["source_time_basis"] and
         is_integer(time["utc_low_ms"]) and is_integer(time["utc_high_ms"]) do
      {:ok, date, _} = DateTime.from_iso8601(fact["source_time"])
      center = DateTime.to_unix(date, :millisecond)
      uncertainty = fact["source_uncertainty_ms"]

      center + uncertainty <= time["utc_low_ms"] and
        time["utc_high_ms"] <= center - uncertainty + contract["freshness_ms"]
    else
      false
    end
  end

  defp typed(%{"value" => value}, %{"type" => "boolean"}, _) when is_boolean(value),
    do: {:known, value}

  defp typed(%{"value" => value}, %{"type" => "enum", "enum" => choices}, _),
    do: if(value in choices, do: {:known, value}, else: :unknown)

  defp typed(%{"value" => value, "unit" => unit}, %{"type" => "integer", "unit" => target}, limits) do
    case Unit.convert(value, unit, target, limits) do
      {:ok, exact} -> {:known, exact}
      _ -> :unknown
    end
  end

  defp typed(_, _, _), do: :unknown

  defp instruction(["literal", truth], stack, _), do: [truth | stack]

  defp instruction([op, binding, expected], stack, values),
    do: [comparison(op, values[binding], expected) | stack]

  defp instruction(["not"], [truth | stack], _),
    do: [if(truth == "unknown", do: "unknown", else: not truth) | stack]

  defp instruction([op, count], stack, _) do
    {args, rest} = Enum.split(stack, count)

    value =
      cond do
        op == "all" and false in args -> false
        op == "any" and true in args -> true
        "unknown" in args -> "unknown"
        op == "all" -> true
        op == "any" -> false
      end

    [value | rest]
  end

  defp comparison("eq", {:known, value}, expected), do: value === expected

  defp comparison("gt", {:known, value}, expected) when is_integer(value) and is_integer(expected),
    do: value > expected

  defp comparison("lt", {:known, value}, expected) when is_integer(value) and is_integer(expected),
    do: value < expected

  defp comparison(_, _, _), do: "unknown"
end
