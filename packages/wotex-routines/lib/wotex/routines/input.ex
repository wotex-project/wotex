defmodule Wotex.Routines.Input do
  @moduledoc """
  Exact inert joins from qualified external profile proposals to routine Facts.

  All clocks, source identities, mapping installation and metadata are explicit.
  A successful Fact grants no admission, current-state or physical-effect claim.
  """

  alias Wotex.Routines.{Error, Fact, InputMapping, InputValidation, Limits, Validation}

  @metadata ~w(id thing_id affordance_type affordance_name source_class source_id source_epoch sequence source_time source_time_trust source_time_basis source_uncertainty_ms received_at receipt_epoch receipt_ms profile_digest replay continuity expires_ms derivation_digest contributors)
  @continuity %{
    "continuous" => {"continuous", "fresh"},
    "baseline" => {"baseline", "fresh"},
    "gap" => {"lost", "fresh"},
    "retained" => {"lost", "retained"},
    "replayed" => {"lost", "replayed"}
  }

  @doc "Revalidates current reader/mapping/source/clock basis and returns a Fact with exact witnesses."
  @spec project(term(), term(), term(), map()) :: {:ok, map()} | {:error, Error.t()}
  def project(proposal, mapping, metadata, context) do
    with :ok <- Validation.fields(context, ~w(registry limits reader_limits)),
         {:ok, limits} <- Limits.new(context["limits"]),
         {:ok, reader_limits} <-
           InputValidation.reader(Wotex.Profiles.Limits, :new, [context["reader_limits"]]),
         {:ok, mapping} <- InputMapping.to_map(mapping, context["registry"], limits),
         {:ok, proposal} <-
           InputValidation.reader(Wotex.Profiles.Proposal, :to_map, [proposal, reader_limits]),
         {:ok, metadata, _} <- InputValidation.admit(metadata, limits, nil),
         :ok <- Validation.fields(metadata, @metadata),
         {:ok, _, _} <-
           InputValidation.admit(
             %{"proposal" => proposal, "mapping" => mapping, "metadata" => metadata},
             limits,
             nil
           ),
         :ok <- basis(proposal, mapping),
         {:ok, seed} <-
           Fact.to_map(
             Map.merge(metadata, %{
               "value" => nil,
               "unit" => mapping["basis"]["value"]["unit"],
               "quality" => "unknown"
             }),
             limits
           ),
         :ok <- source(proposal, mapping, seed, limits),
         :ok <- receipt(proposal, mapping, seed, limits),
         {:ok, value} <- value(proposal, mapping, reader_limits, limits),
         {:ok, fact} <-
           Fact.new(Map.merge(seed, %{"quality" => proposal["quality"], "value" => value}), limits),
         {:ok, digest} <- InputValidation.hash("wotex.routines.input-proposal@1", proposal, limits),
         result = %{
           "fact" => fact,
           "source_proposal_sha256" => digest,
           "mapping_ref" => Map.take(mapping, ~w(id version sha256)),
           "correspondence_ref" => mapping["correspondence_ref"]
         },
         :ok <- Validation.bounded(Map.put(result, "fact", fact.data), limits) do
      {:ok, result}
    else
      error -> InputValidation.refusal(error)
    end
  end

  defp basis(proposal, mapping) do
    pairs = ~w(channel_id affordance profile_sha256 closure_sha256 capture_digest compiler_ref)

    if Enum.all?(pairs, &(proposal[&1] == mapping[&1])) and
         proposal["semantic"] == mapping["semantic_ref"] and
         proposal["unit"] == mapping["external_unit"],
       do: :ok,
       else: Error.refusal(:stale_basis, "/proposal")
  end

  defp source(proposal, mapping, metadata, limits) do
    observation = mapping["observation"]

    with {:ok, sequence} <- sequence(proposal["sequence"], limits),
         {:ok, {continuity, replay}} <- continuity(proposal["continuity"]),
         true <-
           proposal["source_ref"] == observation["source_ref"] and
             metadata["source_id"] == observation["source_ref"] and
             proposal["source_epoch"] == observation["source_epoch"] and
             metadata["source_epoch"] == observation["source_epoch"] and
             metadata["source_class"] == observation["source_class"] and
             metadata["sequence"] == sequence and metadata["continuity"] == continuity and
             metadata["replay"] == replay and
             metadata["profile_digest"] == "sha256:" <> proposal["profile_sha256"] and
             metadata["affordance_type"] == proposal["affordance"]["kind"] and
             metadata["affordance_name"] == proposal["affordance"]["name"],
         :ok <- source_time(proposal["source_time"], observation, metadata, limits) do
      :ok
    else
      false -> Error.refusal(:stale_basis, "/metadata")
      error -> error
    end
  end

  defp sequence(nil, _), do: Error.refusal(:unsupported_representation, "/proposal/sequence")

  defp sequence(value, limits) do
    number = String.to_integer(value)

    if number <= limits.data["max_integer"],
      do: {:ok, number},
      else: Error.refusal(:unsupported_representation, "/proposal/sequence")
  end

  defp continuity(value) do
    case @continuity[value] do
      nil -> Error.refusal(:unsupported_representation, "/proposal/continuity")
      pair -> {:ok, pair}
    end
  end

  defp source_time(nil, observation, metadata, _) do
    if metadata["source_time"] == nil and metadata["source_time_trust"] == "unknown" and
         metadata["source_time_basis"] == nil and metadata["source_uncertainty_ms"] == nil and
         observation["source_time_basis"] == nil,
       do: :ok,
       else: Error.refusal(:stale_basis, "/metadata/source_time")
  end

  defp source_time(time, observation, metadata, limits) do
    with {:ok, uncertainty} <- uncertainty(time["uncertainty_us"], limits),
         {:ok, utc} <- Validation.timestamp(time["utc"], "/proposal/source_time") do
      if same_instant?(metadata["source_time"], utc) and
           metadata["source_time_trust"] == time["trust"] and
           metadata["source_time_basis"] == observation["source_time_basis"] and
           metadata["source_uncertainty_ms"] == uncertainty,
         do: :ok,
         else: Error.refusal(:stale_basis, "/metadata/source_time")
    end
  end

  defp same_instant?(left, right) when is_binary(left) and is_binary(right) do
    with {:ok, left, 0} <- DateTime.from_iso8601(left),
         {:ok, right, 0} <- DateTime.from_iso8601(right) do
      DateTime.compare(left, right) == :eq
    else
      _ -> false
    end
  end

  defp same_instant?(_, _), do: false

  defp uncertainty(nil, _), do: {:ok, nil}

  defp uncertainty(value, limits) do
    millis = div(String.to_integer(value) + 999, 1000)

    with :ok <- Validation.integer(millis, limits, "/proposal/source_time/uncertainty_us", 0),
         do: {:ok, millis}
  end

  defp receipt(proposal, mapping, metadata, limits) do
    clock = mapping["receipt_clock"]
    source = proposal["receipt_time"]
    delta = String.to_integer(source["monotonic_us"]) - String.to_integer(clock["source_origin_us"])

    cond do
      source["epoch"] != clock["source_epoch"] or metadata["receipt_epoch"] != clock["target_epoch"] ->
        Error.refusal(:stale_basis, "/metadata/receipt_epoch")

      rem(delta, 1000) != 0 ->
        Error.refusal(:inexact_conversion, "/proposal/receipt_time")

      true ->
        expected = clock["target_origin_ms"] + div(delta, 1000)

        with :ok <- Validation.integer(expected, limits, "/metadata/receipt_ms", 0) do
          if expected == metadata["receipt_ms"],
            do: :ok,
            else: Error.refusal(:stale_basis, "/metadata/receipt_ms")
        end
    end
  end

  defp value(%{"quality" => quality}, _, _, _) when quality != "usable", do: {:ok, nil}

  defp value(proposal, %{"projection" => "boolean"}, _, _) do
    case proposal["normalized_value"] do
      %{"type" => "boolean", "value" => value} -> {:ok, value}
      _ -> Error.refusal(:unsupported_representation, "/proposal/normalized_value")
    end
  end

  defp value(proposal, %{"projection" => "enum"} = mapping, _, _) do
    case proposal["normalized_value"] do
      %{"type" => "text", "value" => value} ->
        case Enum.find(mapping["enum_table"], &(&1["source"] == value)) do
          nil -> Error.refusal(:unsupported_representation, "/proposal/normalized_value")
          entry -> {:ok, entry["target"]}
        end

      _ ->
        Error.refusal(:unsupported_representation, "/proposal/normalized_value")
    end
  end

  defp value(proposal, mapping, reader_limits, limits) do
    source = mapping["external_unit"]
    unit = mapping["basis"]["value"]["unit"]

    target =
      source
      |> Map.merge(rational(unit, "scale"))
      |> Map.merge(rational(unit, "offset"))

    with {:ok, converted} <-
           InputValidation.reader(Wotex.Profiles.Unit, :convert, [
             proposal["normalized_value"],
             source,
             target,
             reader_limits
           ]),
         {:ok, integer} <- integer(converted, limits),
         true <- integer >= unit["min"] and integer <= unit["max"] do
      {:ok, integer}
    else
      false -> Error.refusal(:unsupported_representation, "/proposal/normalized_value")
      error -> error
    end
  end

  defp rational(unit, key) do
    n = unit[key <> "_n"]
    d = unit[key <> "_d"]
    gcd = Integer.gcd(n, d)

    %{
      (key <> "_n") => Integer.to_string(div(n, gcd)),
      (key <> "_d") => Integer.to_string(div(d, gcd))
    }
  end

  defp integer(%{"type" => type, "value" => value}, limits) when type in ~w(sint uint),
    do: integer_bound(String.to_integer(value), limits)

  defp integer(%{"type" => "decimal", "coefficient" => coefficient, "exponent" => exponent}, limits)
       when exponent in -18..18 do
    n = String.to_integer(coefficient)

    if exponent < 0 do
      d = Integer.pow(10, -exponent)

      if rem(n, d) == 0,
        do: integer_bound(div(n, d), limits),
        else: Error.refusal(:inexact_conversion, "/proposal/normalized_value")
    else
      integer_bound(n * Integer.pow(10, exponent), limits)
    end
  end

  defp integer(_, _), do: Error.refusal(:unsupported_representation, "/proposal/normalized_value")

  defp integer_bound(value, limits) do
    if abs(value) <= limits.data["max_integer"],
      do: {:ok, value},
      else: Error.refusal(:unsupported_representation, "/proposal/normalized_value")
  end
end
