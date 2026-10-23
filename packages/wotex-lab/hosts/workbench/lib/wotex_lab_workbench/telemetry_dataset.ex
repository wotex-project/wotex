defmodule WotexLabWorkbench.TelemetryDataset do
  @moduledoc """
  An immutable capture of the Workbench's bounded session telemetry ring.

  Captures retain every selected event row, including null durations, and bind
  the source scope, query, interval, watermark and loss to their content digest.
  They are raw diagnostic events, distinct from `Wotex.Lab.Metrics.Dataset`
  history-query exports. They perform no normalization, imputation or splitting.
  """

  alias Wotex.Lab.{Error, Telemetry}
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Island.CanonicalJSON

  @fields ~w(sequence at component operation event duration_ms outcome)a
  @maximum_bytes 262_144
  @components Telemetry.components()
  @operations Telemetry.operations()

  @doc "Builds a capture from one scoped query result and an explicit capture time."
  @spec new(String.t(), String.t(), keyword(), map(), DateTime.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def new(id, scope, query, %{samples: samples} = live, %DateTime{} = frozen_at)
      when is_binary(id) and is_binary(scope) and is_list(query) and is_list(samples) and
             length(samples) in 1..2_000 do
    with true <- Keyword.keyword?(query) and Enum.all?(samples, &valid_sample?(&1, scope)),
         sequences = Enum.map(samples, & &1.sequence),
         true <- sequences == Enum.sort(Enum.uniq(sequences)),
         {:ok, content} <- content(live, query, scope),
         {:ok, encoded} <- CanonicalJSON.encode(stringify(content)),
         :ok <- size(encoded) do
      {:ok, Map.merge(content, %{id: id, digest: Digest.bytes(encoded), frozen_at: frozen_at})}
    else
      {:error, %Error{}} = error -> error
      _ -> invalid()
    end
  end

  def new(_, _, _, _, _), do: invalid()

  @doc "Returns the complete JSON representation without truncating captured rows."
  @spec to_map(map()) :: map()
  def to_map(dataset), do: stringify(dataset)

  defp content(
         %{
           samples: samples,
           source: :live,
           interval: %{from: from, to: to} = interval,
           watermark: watermark,
           unit: "ms" = unit,
           loss: loss,
           truncated: truncated
         },
         query,
         scope
       )
       when is_integer(from) and is_integer(to) and from <= to and is_integer(watermark) and
              watermark > 0 and is_boolean(truncated) and is_map(loss) do
    {:ok,
     %{
       schema_version: "wotex-lab-session-dataset/v1",
       source: %{kind: "session_telemetry", scope: scope},
       query: Map.new(Keyword.delete(query, :scope)),
       interval: interval,
       watermark: watermark,
       rows: length(samples),
       samples: Enum.map(samples, &Map.take(&1, @fields)),
       unit: unit,
       ordering: "sequence ascending",
       method: "none (rows kept as queried)",
       missing_policy: "preserve null duration_ms; no imputation",
       split: %{status: "unsplit", strategy: "none"},
       loss: loss,
       truncated: truncated
     }}
  end

  defp content(_, _, _), do: invalid()

  defp valid_sample?(
         %{
           scope: scope,
           sequence: sequence,
           at: at,
           component: component,
           operation: operation,
           event: event,
           duration_ms: duration,
           outcome: outcome
         },
         scope
       ) do
    is_integer(sequence) and sequence > 0 and is_integer(at) and component in @components and
      operation in @operations and event in [:stop, :exception, :measurement] and
      (is_nil(duration) or (is_number(duration) and duration >= 0)) and is_atom(outcome)
  end

  defp valid_sample?(_, _), do: false

  defp size(encoded) when byte_size(encoded) <= @maximum_bytes, do: :ok
  defp size(_), do: {:error, Error.new(:dataset_too_large, :metrics, "dataset exceeds 256 KiB")}

  defp stringify(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp stringify(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), stringify(item)} end)

  defp stringify(value) when is_list(value), do: Enum.map(value, &stringify/1)

  defp stringify(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp stringify(value), do: value

  defp invalid,
    do:
      {:error, Error.new(:invalid_dataset, :metrics, "dataset requires a scoped telemetry capture")}
end
