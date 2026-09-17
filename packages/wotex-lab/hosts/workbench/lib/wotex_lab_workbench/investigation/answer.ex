defmodule WotexLabWorkbench.Investigation.Answer do
  @moduledoc """
  Converts BeamLens terminal results into a small escaped-presentation model.

  It preserves the dependency's fact/hypothesis split, admits no model-supplied
  URL and never emits an Action or approval payload.

  A finding is presented only when its context, observation or hypothesis cites
  at least one `sha256:` digest and every cited digest is in the result's
  `:evidence`, the digests the investigation actually received. A finding that
  cites nothing, or cites a digest no callback returned, is withheld: its text
  is not shown and the missing evidence states why. When every finding is
  withheld the status is `unsupported`. Cited digests are listed as sources
  without links, because a query digest has no page of its own.
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
  @citation ~r/sha256:[0-9a-f]{64}/

  @doc "Builds a browser-safe answer from a broker result and provider disclosure."
  @spec from_result(term(), map()) :: map()
  def from_result({:ok, %{notifications: notifications} = result}, provider)
      when is_list(notifications) do
    notifications = Enum.take(notifications, @max_notifications)
    recorded = result |> Map.get(:evidence, []) |> List.wrap() |> MapSet.new()
    grouped = Enum.group_by(notifications, &grounding(&1, recorded))
    grounded = Map.get(grouped, :grounded, [])

    cond do
      notifications == [] ->
        answer(
          "complete",
          ["The bounded investigation completed without emitting a finding."],
          [],
          ["No finding is not evidence that the run or host is healthy."],
          "Ask a narrower question or inspect the session evidence directly.",
          evidence_source(),
          provider
        )

      grounded == [] ->
        answer(
          "unsupported",
          ["No finding cited evidence that this investigation received."],
          [],
          withheld(grouped),
          "Inspect the session evidence directly; no model finding is shown.",
          evidence_source(),
          provider
        )

      true ->
        answer(
          "complete",
          Enum.map(grounded, &fact/1),
          grounded |> Enum.map(&field(&1, "hypothesis")) |> present_strings(),
          missing_evidence(grounded) ++ withheld(grouped),
          "Review the cited evidence before making any separate policy decision.",
          sources(grounded),
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

  defp grounding(notification, recorded) do
    cited = citations(notification)

    cond do
      cited == [] -> :uncited
      Enum.all?(cited, &MapSet.member?(recorded, &1)) -> :grounded
      true -> :unrecorded
    end
  end

  defp citations(notification) do
    ["context", "observation", "hypothesis"]
    |> Enum.map(&field(notification, &1))
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(&Regex.scan(@citation, &1))
    |> List.flatten()
    |> Enum.uniq()
  end

  defp withheld(grouped) do
    [
      withheld_text(
        grouped,
        :uncited,
        "cited no recorded query or run-summary digest and was withheld."
      ),
      withheld_text(
        grouped,
        :unrecorded,
        "cited a digest that no callback returned and was withheld."
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp withheld_text(grouped, key, reason) do
    case length(Map.get(grouped, key, [])) do
      0 -> nil
      1 -> "1 finding " <> reason
      count -> "#{count} findings " <> String.replace(reason, "was withheld", "were withheld")
    end
  end

  defp sources(notifications) do
    digest_sources =
      notifications
      |> Enum.flat_map(&citations/1)
      |> Enum.uniq()
      |> Enum.map(&%{label: "Recorded evidence " <> &1, href: nil})

    snapshot_sources =
      notifications
      |> Enum.flat_map(&snapshots/1)
      |> Enum.map(&field(&1, "id"))
      |> present_strings()
      |> Enum.uniq()
      |> Enum.map(&%{label: "BeamLens snapshot #{&1}", href: "/evidence"})

    Enum.uniq_by(digest_sources ++ snapshot_sources ++ evidence_source(), & &1.label)
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
