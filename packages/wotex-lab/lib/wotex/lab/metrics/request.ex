defmodule Wotex.Lab.Metrics.Request do
  @moduledoc """
  Closed, string-keyed metric query input for inspection frontends.

  `decode/3` accepts only schema version, catalogue metric/aggregation, finite
  filters, UTC endpoints, step and optional quantile. Scope and limits come
  separately from authenticated host context, never from request text. No
  atoms, endpoints, SQL, modules or callbacks are created from input. Transport
  hosts must bound encoded input before JSON decoding; this boundary validates
  the resulting bounded field structure, not a raw HTTP body.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Catalogue, Query}

  @keys ~w(schema_version metric aggregation filters quantile start_at end_at step_ms)
  @metrics Map.new(Catalogue.metrics(), &{Atom.to_string(&1.id), &1.id})
  @aggregations Map.new(Query.aggregations(), &{Atom.to_string(&1), &1})
  @dimensions Map.new(Catalogue.dimensions(), fn {key, values} ->
                {Atom.to_string(key), {key, Map.new(values, &{Atom.to_string(&1), &1})}}
              end)

  @doc "Decodes caller fields with separately supplied server scope and query limits."
  @spec decode(term(), map(), map()) :: {:ok, Query.t()} | {:error, Error.t()}
  def decode(request, scope, limits) when is_map(request) and map_size(request) <= 8 do
    with true <- Enum.all?(Map.keys(request), &(&1 in @keys)),
         true <- request["schema_version"] == Query.schema_version(),
         {:ok, metric} <- enum(@metrics, request["metric"]),
         {:ok, aggregation} <- enum(@aggregations, request["aggregation"]),
         {:ok, filters} <- filters(Map.get(request, "filters", %{})),
         {:ok, start_at} <- utc(request["start_at"]),
         {:ok, end_at} <- utc(request["end_at"]) do
      Query.new(
        scope: scope,
        limits: limits,
        metric: metric,
        aggregation: aggregation,
        filters: filters,
        start_at: start_at,
        end_at: end_at,
        step_ms: request["step_ms"],
        quantile: request["quantile"]
      )
    else
      _invalid -> invalid()
    end
  end

  def decode(_request, _scope, _limits), do: invalid()

  defp enum(values, key) when is_binary(key) and byte_size(key) <= 128,
    do: Map.fetch(values, key)

  defp enum(_values, _key), do: :error

  defp filters(filters) when is_map(filters) and map_size(filters) <= map_size(@dimensions) do
    Enum.reduce_while(filters, {:ok, %{}}, fn {key, value}, {:ok, result} ->
      with {:ok, {dimension, values}} <- enum(@dimensions, key),
           {:ok, admitted} <- enum(values, value) do
        {:cont, {:ok, Map.put(result, dimension, admitted)}}
      else
        _invalid -> {:halt, :error}
      end
    end)
  end

  defp filters(_filters), do: :error

  defp utc(value) when is_binary(value) and byte_size(value) in 20..35 do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, 0} -> {:ok, datetime}
      _invalid -> :error
    end
  end

  defp utc(_value), do: :error

  defp invalid,
    do: {:error, Error.new(:invalid_request, :query, "query fields are not admitted")}
end
