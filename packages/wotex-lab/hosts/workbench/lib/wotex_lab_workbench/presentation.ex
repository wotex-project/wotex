defmodule WotexLabWorkbench.Presentation do
  @moduledoc """
  Bounded, inert presentation retained for one documentation round trip.

  The Workbench supplies already admitted server values. A snapshot contains
  no worker, command, decision or refresh subscription. Restoring it never
  executes a read, query, run or model request.
  """

  alias Wotex.Lab.Error

  @keys ~w(path layout experiment_forms selected_experiment canvas_readings
           canvas_selection metric_draft prompt metric_result answer investigation_results)a
  @maximum_bytes 256 * 1_024

  @doc "Admits only the closed presentation fields within a 256 KiB JSON budget."
  @spec admit(term()) :: {:ok, map()} | {:error, Error.t()}
  def admit(value) when is_map(value) and not is_struct(value) do
    with true <- Enum.sort(Map.keys(value)) == Enum.sort(@keys),
         true <- path?(value.path),
         true <- is_map(value.experiment_forms) and map_size(value.experiment_forms) <= 3,
         true <- is_map(value.canvas_readings) and map_size(value.canvas_readings) <= 31,
         true <- is_map(value.metric_draft),
         true <- is_list(value.investigation_results) and length(value.investigation_results) <= 8,
         true <- :erlang.external_size(value) <= @maximum_bytes and inert?(value, 0),
         {:ok, encoded} <- Jason.encode(json_value(value)),
         true <- byte_size(encoded) <= @maximum_bytes do
      {:ok, value}
    else
      _ -> invalid()
    end
  end

  def admit(_), do: invalid()

  @doc "Admits only local Workbench destinations, never a documentation or external route."
  @spec path?(term()) :: boolean()
  def path?(value) when is_binary(value) and byte_size(value) <= 2_048 do
    uri = URI.parse(value)

    is_nil(uri.scheme) and is_nil(uri.host) and is_nil(uri.fragment) and
      (uri.path in ~w(/ /experiments /things /metrics /evidence) or
         Regex.match?(~r{\A/runs/[A-Za-z0-9._:-]+\z}, uri.path || ""))
  end

  def path?(_), do: false

  defp inert?(_, depth) when depth > 24, do: false

  defp inert?(%module{} = value, depth) do
    module in [Wotex.Lab.Error, WotexLabWorkbench.Chart] and
      inert?(Map.from_struct(value), depth + 1)
  end

  defp inert?(value, depth) when is_map(value),
    do: Enum.all?(value, fn {k, v} -> (is_atom(k) or is_binary(k)) and inert?(v, depth + 1) end)

  defp inert?(value, depth) when is_list(value),
    do: length(value) <= 4_096 and Enum.all?(value, &inert?(&1, depth + 1))

  defp inert?(value, depth) when is_tuple(value),
    do: tuple_size(value) <= 2 and inert?(Tuple.to_list(value), depth + 1)

  defp inert?(value, _), do: is_binary(value) or is_number(value) or is_atom(value)

  defp json_value(%_{} = value), do: json_value(Map.from_struct(value))

  defp json_value(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), json_value(v)} end)

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)
  defp json_value(value) when is_tuple(value), do: json_value(Tuple.to_list(value))

  defp json_value(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp json_value(value), do: value

  defp invalid,
    do: {:error, Error.new(:invalid_presentation, :workbench, "Workbench state cannot be retained")}
end
