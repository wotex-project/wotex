defmodule Wotex.JSON do
  @moduledoc false

  alias Wotex.Error

  @default_max_depth 64
  @default_max_nodes 100_000

  @type json_scalar :: nil | boolean() | number() | String.t()
  @type json_value :: json_scalar() | [json_value()] | %{String.t() => json_value()}

  @spec validate(term(), keyword()) :: :ok | {:error, Error.t()}
  def validate(value, opts \\ []) do
    max_depth = positive_limit(opts, :max_depth, @default_max_depth)
    max_nodes = positive_limit(opts, :max_nodes, @default_max_nodes)

    case walk(value, 0, 0, max_depth, max_nodes, "/") do
      {:ok, _nodes} -> :ok
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @spec encode(json_value(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, opts \\ []) do
    with :ok <- validate(value, opts),
         {:ok, encoded} <- encode_value(value) do
      {:ok, IO.iodata_to_binary(encoded)}
    end
  end

  @spec pointer_segment(String.t()) :: String.t()
  def pointer_segment(segment) do
    segment
    |> String.replace("~", "~0")
    |> String.replace("/", "~1")
  end

  defp walk(_value, _depth, nodes, _max_depth, max_nodes, path) when nodes >= max_nodes do
    {:error,
     Error.new(
       :node_limit_exceeded,
       :value,
       "JSON value exceeds the configured node limit",
       path,
       %{max_nodes: max_nodes}
     )}
  end

  defp walk(_value, depth, _nodes, max_depth, _max_nodes, path) when depth > max_depth do
    {:error,
     Error.new(
       :depth_limit_exceeded,
       :value,
       "JSON value exceeds the configured nesting depth",
       path,
       %{max_depth: max_depth}
     )}
  end

  defp walk(value, _depth, nodes, _max_depth, _max_nodes, _path)
       when is_nil(value) or is_boolean(value) or is_integer(value) or is_binary(value) do
    {:ok, nodes + 1}
  end

  defp walk(value, _depth, nodes, _max_depth, _max_nodes, path) when is_float(value) do
    case Jason.encode(value) do
      {:ok, _json} ->
        {:ok, nodes + 1}

      {:error, _reason} ->
        {:error, Error.new(:invalid_number, :value, "JSON numbers must be finite", path)}
    end
  end

  defp walk(values, depth, nodes, max_depth, max_nodes, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, nodes + 1}, fn {value, index}, {:ok, count} ->
      case walk(value, depth + 1, count, max_depth, max_nodes, join(path, index)) do
        {:ok, next_count} -> {:cont, {:ok, next_count}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp walk(value, depth, nodes, max_depth, max_nodes, path) when is_map(value) do
    Enum.reduce_while(value, {:ok, nodes + 1}, fn
      {key, child}, {:ok, count} when is_binary(key) ->
        case walk(child, depth + 1, count, max_depth, max_nodes, join(path, key)) do
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
            path,
            %{key: inspect(key, limit: 10, printable_limit: 40)}
          )}}
    end)
  end

  defp walk(_value, _depth, _nodes, _max_depth, _max_nodes, path) do
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
    with {:ok, entries} <- value |> Enum.map(&encode_value/1) |> collect() do
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
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, values} -> {:cont, {:ok, [value | values]}}
      {:error, error}, _acc -> {:halt, {:error, error}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, error} -> {:error, error}
    end
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
