defmodule Wotex.Profiles.Interpreter do
  @moduledoc """
  Exact mechanical projection of supplied decoded reports into inert proposals.

  Retained input, capture, source quality and receipt provenance are explicit.
  A proposal makes no source-authenticity, freshness, qualification or authority
  claim. No transport, clock, store, registry or effect is consulted.
  """

  alias Wotex.Profiles.{Arithmetic, Binding, Error, Grammar, Instance, Limits, Projection, Report}

  @identity %{"scale_n" => "1", "scale_d" => "1", "offset_n" => "0", "offset_d" => "1"}
  @provenance ~w(channel_id quality quality_reason continuity source_ref source_epoch sequence source_time receipt_time profile_sha256)

  @doc "Revalidates the projection and report, preserving provenance and refusing stale basis or inexact values."
  @spec project(term(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def project(projection, report, limits) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, data} <- Projection.to_map(projection, limits),
         {:ok, report} <- Report.header(report, limits),
         :ok <- basis(data, report),
         {:ok, value} <- value(report["value"]),
         {:ok, plan} <- plan(data["channel_plans"], report["channel_id"]),
         binding =
           Enum.find(
             projection.inputs["closure"]["bindings"],
             &(Map.take(&1, ~w(id version sha256)) == data["binding"])
           ),
         {:ok, binding} <- Binding.new(binding, limits),
         {:ok, normalized, quality, reason, interpretation} <-
           normalize(plan, binding.data, value, report, limits),
         output =
           Map.take(report, @provenance)
           |> Map.merge(%{
             "affordance" => plan["affordance"],
             "semantic" => plan["semantic"],
             "unit" => plan["definition"]["unit"],
             "normalized_value" => normalized,
             "quality" => quality,
             "quality_reason" => reason,
             "closure_sha256" => data["closure_sha256"],
             "capture_digest" => data["capture_digest"],
             "compiler_ref" => data["compiler_ref"],
             "interpretation" => interpretation
           }),
         {:ok, _, _} <- Grammar.admit(output, limits) do
      {:ok, output}
    end
  end

  defp basis(data, report) do
    if Enum.all?(~w(profile_sha256 binding capture_epoch), &(data[&1] == report[&1])),
      do: :ok,
      else: Error.refusal(:stale_basis, "/report")
  end

  defp value(value) do
    case Wotex.Runtime.Codec.Value.validate(value) do
      {:ok, _} = success -> success
      _ -> Error.refusal(:invalid_input, "/report/value")
    end
  end

  defp plan(plans, channel_id) do
    case Enum.find(plans, &(&1["channel_id"] == channel_id)) do
      %{"disposition" => "supported"} = plan -> {:ok, plan}
      _ -> Error.refusal(:unsupported_semantics, "/report/channel_id")
    end
  end

  defp normalize(_, _, _, %{"quality" => quality, "quality_reason" => reason}, _)
       when quality != "usable",
       do: {:ok, %{"type" => "null"}, quality, reason, "unconverted"}

  defp normalize(plan, binding, value, _, limits) do
    with :ok <- Instance.c02(value, binding["raw_value_schema"], limits, "/report/value") do
      if value in plan["invalid_values"] do
        {:ok, %{"type" => "null"}, "invalid", "profile_sentinel", "unconverted"}
      else
        converted(plan, value, limits)
      end
    end
  end

  defp converted(plan, value, limits) do
    with {:ok, normalized} <- convert(value, plan["conversion"], limits),
         :ok <-
           Instance.c02(normalized, plan["definition"]["value_schema"], limits, "/report/value") do
      interpretation = if plan["conversion"] == nil, do: "unconverted", else: "profile_declared"
      {:ok, normalized, "usable", nil, interpretation}
    end
  end

  defp convert(value, nil, _), do: {:ok, value}

  defp convert(value, %{"kind" => "affine"} = conversion, limits),
    do: Arithmetic.coordinates(value, conversion, @identity, limits)

  defp convert(value, %{"kind" => "table", "entries" => entries}, _) do
    case Enum.find(entries, &(&1["source"] == value)) do
      nil -> Error.refusal(:unsupported_semantics, "/report/value")
      entry -> {:ok, entry["target"]}
    end
  end
end
