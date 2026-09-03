defmodule Wotex.JSON do
  @moduledoc false

  alias Wotex.Error

  @default_max_depth 64
  @default_max_nodes 100_000

  @type json_scalar :: nil | boolean() | number() | String.t()
  @type json_value :: json_scalar() | [json_value()] | %{String.t() => json_value()}

  @doc "Validates native JSON-value semantics and configured resource limits."
  @spec validate(term(), keyword()) :: :ok | {:error, Error.t()}
  def validate(value, opts \\ []) do
    max_depth = positive_limit(opts, :max_depth, @default_max_depth)
    max_nodes = positive_limit(opts, :max_nodes, @default_max_nodes)

    state = %{depth: 0, nodes: 0, max_depth: max_depth, max_nodes: max_nodes, path: "/"}

    case walk(value, state) do
      {:ok, _nodes} -> :ok
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @doc "Encodes a valid JSON value with recursively sorted object keys."
  @spec encode(json_value(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, opts \\ []) do
    with :ok <- validate(value, opts),
         {:ok, encoded} <- encode_value(value) do
      {:ok, IO.iodata_to_binary(encoded)}
    end
  end

  @doc "Escapes one RFC 6901 JSON Pointer path segment."
  @spec pointer_segment(String.t()) :: String.t()
  def pointer_segment(segment) do
    segment
    |> String.replace("~", "~0")
    |> String.replace("/", "~1")
  end

  defp walk(_value, %{nodes: nodes, max_nodes: max_nodes, path: path})
       when nodes >= max_nodes do
    {:error,
     Error.new(
       :node_limit_exceeded,
       :value,
       "JSON value exceeds the configured node limit",
       path,
       %{max_nodes: max_nodes}
     )}
  end

  defp walk(_value, %{depth: depth, max_depth: max_depth, path: path})
       when depth > max_depth do
    {:error,
     Error.new(
       :depth_limit_exceeded,
       :value,
       "JSON value exceeds the configured nesting depth",
       path,
       %{max_depth: max_depth}
     )}
  end

  defp walk(value, %{nodes: nodes})
       when is_nil(value) or is_boolean(value) or is_integer(value) or is_binary(value) do
    {:ok, nodes + 1}
  end

  defp walk(value, %{nodes: nodes, path: path}) when is_float(value) do
    case Jason.encode(value) do
      {:ok, _json} -> {:ok, nodes + 1}
      {:error, _reason} -> {:error, Error.new(:invalid_number, :value, "invalid JSON number", path)}
    end
  end

  defp walk(values, state) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, state.nodes + 1}, fn {value, index}, {:ok, count} ->
      child_state = child_state(state, count, index)

      case walk(value, child_state) do
        {:ok, next_count} -> {:cont, {:ok, next_count}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp walk(value, state) when is_map(value) do
    Enum.reduce_while(value, {:ok, state.nodes + 1}, fn
      {key, child}, {:ok, count} when is_binary(key) ->
        case walk(child, child_state(state, count, key)) do
          {:ok, next_count} -> {:cont, {:ok, next_count}}
          {:error, error} -> {:halt, {:error, error}}
        end

      {key, _child}, _acc ->
        {:halt,
         {:error,
          Error.new(
            :non_string_key,
            :value,
            "JSON object keys must be strings",
            state.path,
            %{key: inspect(key, limit: 10, printable_limit: 40)}
          )}}
    end)
  end

  defp walk(_value, %{path: path}) do
    {:error,
     Error.new(
       :invalid_json_value,
       :value,
       "Value cannot be represented in JSON",
       path
     )}
  end

  defp encode_value(value) when is_map(value) do
    encoded_entries =
      value
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, child} ->
        with {:ok, encoded_key} <- Jason.encode_to_iodata(key),
             {:ok, encoded_child} <- encode_value(child) do
          {:ok, [encoded_key, ?:, encoded_child]}
        end
      end)

    with {:ok, entries} <- collect(encoded_entries) do
      {:ok, [?{, Enum.intersperse(entries, ?,), ?}]}
    end
  end

  defp encode_value(value) when is_list(value) do
    encoded_entries = Enum.map(value, &encode_value/1)

    with {:ok, entries} <- collect(encoded_entries) do
      {:ok, [?[, Enum.intersperse(entries, ?,), ?]]}
    end
  end

  defp encode_value(value) do
    case Jason.encode_to_iodata(value) do
      {:ok, encoded} ->
        {:ok, encoded}

      {:error, reason} ->
        {:error,
         Error.new(:encode_failed, :encode, "JSON encoding failed", "/", %{
           reason: inspect(reason, limit: 20, printable_limit: 80)
         })}
    end
  end

  defp collect(results) do
    result =
      Enum.reduce_while(results, {:ok, []}, fn
        {:ok, value}, {:ok, values} -> {:cont, {:ok, [value | values]}}
        {:error, error}, _acc -> {:halt, {:error, error}}
      end)

    case result do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, error} -> {:error, error}
    end
  end

  defp child_state(state, nodes, segment) do
    %{state | depth: state.depth + 1, nodes: nodes, path: join(state.path, segment)}
  end

  defp positive_limit(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> default
    end
  end

  defp join("/", segment), do: "/" <> pointer_segment(to_string(segment))
  defp join(path, segment), do: path <> "/" <> pointer_segment(to_string(segment))
end
