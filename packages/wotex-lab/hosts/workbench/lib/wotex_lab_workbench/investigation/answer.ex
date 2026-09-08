defmodule WotexLabWorkbench.Investigation.Answer do
  @moduledoc """
  Converts BeamLens terminal results into a small escaped-presentation model.

  It preserves the dependency's fact/hypothesis split, admits no model-supplied
  URL and never emits an Action or approval payload.
  """

  @max_notifications 8
  @field_atoms %{
    "context" => :context,
    "observation" => :observation,
    "hypothesis" => :hypothesis,
    "snapshots" => :snapshots,
    "id" => :id
  }
  @max_text_chars 1_024

  @doc "Builds a browser-safe answer from a broker result and provider disclosure."
  @spec from_result(term(), map()) :: map()
  def from_result({:ok, %{notifications: notifications}}, provider) when is_list(notifications) do
    notifications = Enum.take(notifications, @max_notifications)

    if notifications == [] do
      answer(
        "complete",
        ["The bounded investigation completed without emitting a finding."],
        [],
        ["No finding is not evidence that the run or host is healthy."],
        "Ask a narrower question or inspect the session evidence directly.",
        evidence_source(),
        provider
      )
    else
      answer(
        "complete",
        Enum.map(notifications, &fact/1),
        notifications |> Enum.map(&field(&1, "hypothesis")) |> present_strings(),
        missing_evidence(notifications),
        "Review the cited evidence before making any separate policy decision.",
        sources(notifications),
        provider
      )
    end
  end

  def from_result({:error, reason}, provider) do
    {status, observed, next_check} = failure(reason)

    answer(
      status,
      [observed],
      [],
      ["No model result is treated as evidence."],
      next_check,
      evidence_source(),
      provider
    )
  end

  def from_result(_result, provider), do: from_result({:error, :provider_failure}, provider)

  defp fact(notification) do
    [field(notification, "context"), field(notification, "observation")]
    |> present_strings()
    |> Enum.join(" — ")
    |> case do
      "" -> "BeamLens emitted a finding without presentable factual text."
      text -> text
    end
  end

  defp missing_evidence(notifications) do
    if Enum.any?(notifications, &(snapshots(&1) == [])),
      do: ["At least one finding contains no snapshot reference."],
      else: []
  end

  defp sources(notifications) do
    snapshot_sources =
      notifications
      |> Enum.flat_map(&snapshots/1)
      |> Enum.map(&field(&1, "id"))
      |> present_strings()
      |> Enum.uniq()
      |> Enum.map(&%{label: "BeamLens snapshot #{&1}", href: "/evidence"})

    Enum.uniq_by(snapshot_sources ++ evidence_source(), & &1.label)
  end

  defp snapshots(notification) do
    case field(notification, "snapshots") do
      snapshots when is_list(snapshots) -> Enum.take(snapshots, 16)
      _other -> []
    end
  end

  defp failure(:investigation_cancelled),
    do:
      {"cancelled", "The investigation was cancelled and its context was cleared.",
       "Submit a new question if needed."}

  defp failure(:investigation_timeout),
    do:
      {"timed out", "The investigation reached its hard deadline and was terminated.",
       "Narrow the question or inspect evidence directly."}

  defp failure(:owner_down),
    do:
      {"cancelled", "The investigation owner disconnected and the worker was terminated.",
       "Reconnect before submitting a new question."}

  defp failure(:session_revoked),
    do:
      {"cancelled", "The session expired or was revoked and the investigation was terminated.",
       "Open a fresh session before submitting another question."}

  defp failure(_reason),
    do:
      {"unavailable", "The investigation provider did not produce an admitted result.",
       "Check the disclosed provider state or inspect evidence directly."}

  defp answer(status, observed, hypotheses, missing, next_check, sources, provider) do
    %{
      status: status,
      observed: present_strings(observed),
      hypotheses: present_strings(hypotheses),
      missing: present_strings(missing),
      next_check: bounded_text(next_check),
      sources: sources,
      provider: provider_label(provider),
      model: model_label(provider)
    }
  end

  defp provider_label(%{provider: provider}) when provider in [:codex, :ollama],
    do: Atom.to_string(provider)

  defp provider_label(_provider), do: "not reported"

  defp model_label(%{model: model}) when is_binary(model), do: bounded_text(model)
  defp model_label(_provider), do: "not reported"

  defp evidence_source, do: [%{label: "Bounded session evidence", href: "/evidence"}]

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, @field_atoms[key])
  defp field(_value, _key), do: nil

  defp present_strings(values) do
    values
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.map(&bounded_text/1)
  end

  defp bounded_text(text), do: String.slice(text, 0, @max_text_chars)
end
