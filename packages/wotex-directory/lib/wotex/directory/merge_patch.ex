defmodule Wotex.Directory.MergePatch do
  @moduledoc """
  Bounded RFC 7396 JSON Merge Patch mechanics for JSON-compatible maps.

  The root patch must be an object because Discovery PATCH accepts a Partial
  Thing Description. Object keys must be strings and all values must be JSON
  compatible.

  ## Merge Patch warning

  RFC 7396 gives `null` deletion semantics and replaces arrays as whole values;
  it does not merge array elements. The directory revalidates the complete
  merged Thing Description and separately protects server-owned registration
  members before persistence.
  """

  alias Wotex.Directory.Error

  @type reason :: :invalid_json_value | :maximum_depth_exceeded | :maximum_nodes_exceeded

  @doc """
  Applies a depth- and node-bounded RFC 7396 JSON Merge Patch.

  A refusal is a `Wotex.Directory.Error` whose `path` is the JSON Pointer of
  the offending patch member and whose `details` carry the structural
  `reason`. No patch content appears in the message.
  """
  @spec apply(map(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def apply(target, patch, options \\ [])

  def apply(target, patch, options)
      when is_map(target) and is_map(patch) and is_list(options) do
    with :ok <- validate_options(options),
         maximum_depth <- Keyword.get(options, :maximum_depth, 64),
         maximum_nodes <- Keyword.get(options, :maximum_nodes, 100_000),
         :ok <- validate_limit(maximum_depth),
         :ok <- validate_limit(maximum_nodes),
         {:ok, _nodes} <- validate_json(patch, "", 0, 0, maximum_depth, maximum_nodes),
         {:ok, result} <- merge(target, patch, "", 0, maximum_depth) do
      {:ok, result}
    end
  end

  def apply(_target, _patch, _options), do: invalid("/")

  defp merge(_target, _patch, path, depth, maximum_depth) when depth > maximum_depth,
    do: refuse(path, :maximum_depth_exceeded)

  defp merge(target, patch, path, depth, maximum_depth) do
    initial = if is_map(target), do: target, else: %{}

    patch
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.reduce_while({:ok, initial}, fn
      {key, nil}, {:ok, result} ->
        {:cont, {:ok, Map.delete(result, key)}}

      {key, value}, {:ok, result} when is_map(value) ->
        case merge(Map.get(result, key), value, pointer(path, key), depth + 1, maximum_depth) do
          {:ok, merged} -> {:cont, {:ok, Map.put(result, key, merged)}}
          {:error, error} -> {:halt, {:error, error}}
        end

      {key, value}, {:ok, result} ->
        {:cont, {:ok, Map.put(result, key, value)}}
    end)
  end

  defp validate_json(_value, path, depth, _nodes, maximum_depth, _maximum_nodes)
       when depth > maximum_depth,
       do: refuse(path, :maximum_depth_exceeded)

  defp validate_json(_value, path, _depth, nodes, _maximum_depth, maximum_nodes)
       when nodes >= maximum_nodes,
       do: refuse(path, :maximum_nodes_exceeded)

  defp validate_json(value, _path, _depth, nodes, _maximum_depth, _maximum_nodes)
       when is_nil(value) or is_boolean(value) or is_binary(value),
       do: {:ok, nodes + 1}

  defp validate_json(value, _path, _depth, nodes, _maximum_depth, _maximum_nodes)
       when is_integer(value),
       do: {:ok, nodes + 1}

  defp validate_json(value, _path, _depth, nodes, _maximum_depth, _maximum_nodes)
       when is_float(value) and value == value,
       do: {:ok, nodes + 1}

  defp validate_json(values, path, depth, nodes, maximum_depth, maximum_nodes)
       when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, nodes + 1}, fn {value, index}, {:ok, count} ->
      case validate_json(
             value,
             pointer(path, Integer.to_string(index)),
             depth + 1,
             count,
             maximum_depth,
             maximum_nodes
           ) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp validate_json(values, path, depth, nodes, maximum_depth, maximum_nodes)
       when is_map(values) do
    if Enum.all?(Map.keys(values), &is_binary/1) do
      values
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.reduce_while({:ok, nodes + 1}, fn {key, value}, {:ok, count} ->
        case validate_json(
               value,
               pointer(path, key),
               depth + 1,
               count,
               maximum_depth,
               maximum_nodes
             ) do
          {:ok, updated} -> {:cont, {:ok, updated}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    else
      invalid(pointer(path, ""))
    end
  end

  defp validate_json(_value, path, _depth, _nodes, _maximum_depth, _maximum_nodes),
    do: invalid(pointer(path, ""))

  defp validate_limit(value) when is_integer(value) and value > 0, do: :ok
  defp validate_limit(_value), do: invalid("/")

  defp validate_options(options) do
    allowed = [:maximum_depth, :maximum_nodes]

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) do
      :ok
    else
      invalid("/")
    end
  end

  defp pointer("", key), do: "/" <> escape(key)
  defp pointer(path, ""), do: path
  defp pointer(path, key), do: path <> "/" <> escape(key)

  defp escape(key) do
    key |> String.replace("~", "~0") |> String.replace("/", "~1")
  end

  defp invalid(path), do: refuse(path, :invalid_json_value)

  defp refuse(path, reason) do
    {:error,
     Error.new(:invalid_request, :patch, :patch,
       path: normalize(path),
       details: %{reason: reason}
     )}
  end

  defp normalize(""), do: "/"
  defp normalize(path), do: path
end
