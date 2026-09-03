defmodule WotexContinuum.Limits do
  @moduledoc """
  Resource limits enforced before and after JSON decoding.

  The byte and lexical scan rejects oversized input, invalid UTF-8, excessive
  string size, and excessive nesting before allocation-heavy decoding. The
  post-decode pass then bounds collections, detects duplicate object members,
  copies strings away from the source binary, and rechecks depth.

  Limits are explicit values so consumers can choose policy without ambient
  configuration.
  """

  alias WotexContinuum.Error

  @enforce_keys [:max_bytes, :max_depth, :max_collection_size, :max_string_bytes]
  defstruct max_bytes: 1_048_576,
            max_depth: 32,
            max_collection_size: 10_000,
            max_string_bytes: 262_144

  @type t :: %__MODULE__{
          max_bytes: pos_integer(),
          max_depth: pos_integer(),
          max_collection_size: pos_integer(),
          max_string_bytes: pos_integer()
        }

  @doc "Returns conservative default decoder limits."
  @spec defaults() :: %__MODULE__{
          max_bytes: 1_048_576,
          max_depth: 32,
          max_collection_size: 10_000,
          max_string_bytes: 262_144
        }
  def defaults do
    %__MODULE__{
      max_bytes: 1_048_576,
      max_depth: 32,
      max_collection_size: 10_000,
      max_string_bytes: 262_144
    }
  end

  @doc "Builds validated limits from a keyword list or map."
  @spec new(keyword() | map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = limits), do: validate(limits)

  def new(options) when is_list(options) do
    if Keyword.keyword?(options) do
      options
      |> Map.new()
      |> new()
    else
      invalid_options()
    end
  end

  def new(options) when is_map(options) do
    allowed = Map.keys(Map.from_struct(defaults()))

    with {:ok, normalized} <- WotexContinuum.Validation.normalize(options, allowed) do
      defaults()
      |> Map.from_struct()
      |> Map.merge(normalized)
      |> then(&struct!(__MODULE__, &1))
      |> validate()
    end
  end

  def new(_), do: invalid_options()

  @doc false
  @spec preflight(binary(), t()) :: :ok | {:error, Error.t()}
  def preflight(source, %__MODULE__{} = limits) when is_binary(source) do
    cond do
      byte_size(source) > limits.max_bytes ->
        Error.error(:limit_exceeded, [], "JSON source exceeds the byte limit", %{
          limit: limits.max_bytes
        })

      not String.valid?(source) ->
        Error.error(:invalid_utf8, [], "JSON source is not valid UTF-8")

      true ->
        scan_depth(source, limits)
    end
  end

  @doc false
  @spec normalize_decoded(term(), t()) :: {:ok, term()} | {:error, Error.t()}
  def normalize_decoded(value, %__MODULE__{} = limits) do
    normalize_decoded(value, limits, [], 0)
  end

  defp validate(%__MODULE__{} = limits) do
    fields = Map.from_struct(limits)

    case Enum.find(fields, fn {_, value} -> not (is_integer(value) and value > 0) end) do
      nil -> {:ok, limits}
      {key, _} -> Error.error(:invalid_limit, [Atom.to_string(key)], "limit must be positive")
    end
  end

  defp invalid_options, do: Error.error(:invalid_type, [], "expected limit options")

  defp scan_depth(source, limits) do
    result =
      source
      |> :binary.bin_to_list()
      |> Enum.reduce_while({:ok, 0, false, false, 0}, fn byte,
                                                         {:ok, depth, in_string, escaped,
                                                          string_size} ->
        scan_byte(byte, {depth, in_string, escaped, string_size}, limits)
      end)

    case result do
      {:ok, _, _, _, _} -> :ok
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp scan_byte(_, {depth, true, true, string_size}, _) do
    {:cont, {:ok, depth, true, false, string_size + 1}}
  end

  defp scan_byte(?\\, {depth, true, false, string_size}, _) do
    {:cont, {:ok, depth, true, true, string_size + 1}}
  end

  defp scan_byte(?", {depth, true, false, _}, _) do
    {:cont, {:ok, depth, false, false, 0}}
  end

  defp scan_byte(_, {depth, true, false, string_size}, limits) do
    next_size = string_size + 1

    if next_size > limits.max_string_bytes do
      {:halt,
       Error.error(:limit_exceeded, [], "JSON string exceeds the byte limit", %{
         limit: limits.max_string_bytes
       })}
    else
      {:cont, {:ok, depth, true, false, next_size}}
    end
  end

  defp scan_byte(?", {depth, false, _, _}, _) do
    {:cont, {:ok, depth, true, false, 0}}
  end

  defp scan_byte(byte, {depth, false, _, _}, limits) when byte in [?{, ?[] do
    next_depth = depth + 1

    if next_depth > limits.max_depth do
      {:halt,
       Error.error(:limit_exceeded, [], "JSON exceeds the nesting limit", %{
         limit: limits.max_depth
       })}
    else
      {:cont, {:ok, next_depth, false, false, 0}}
    end
  end

  defp scan_byte(byte, {depth, false, _, _}, _) when byte in [?}, ?]] do
    {:cont, {:ok, max(depth - 1, 0), false, false, 0}}
  end

  defp scan_byte(_, {depth, false, _, _}, _) do
    {:cont, {:ok, depth, false, false, 0}}
  end

  defp normalize_decoded(_, limits, path, depth) when depth > limits.max_depth do
    Error.error(:limit_exceeded, path, "decoded value exceeds the nesting limit")
  end

  defp normalize_decoded(%Jason.OrderedObject{values: pairs}, limits, path, depth) do
    if length(pairs) > limits.max_collection_size do
      Error.error(:limit_exceeded, path, "object exceeds the member limit")
    else
      Enum.reduce_while(pairs, {:ok, %{}}, &normalize_object_pair(&1, &2, limits, path, depth))
    end
  end

  defp normalize_decoded(value, limits, path, depth) when is_list(value) do
    if length(value) > limits.max_collection_size do
      Error.error(:limit_exceeded, path, "array exceeds the member limit")
    else
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, &normalize_list_item(&1, &2, limits, path, depth))
      |> reverse_normalized()
    end
  end

  defp normalize_decoded(value, limits, path, _) when is_binary(value) do
    if byte_size(value) <= limits.max_string_bytes,
      do: {:ok, :binary.copy(value)},
      else: Error.error(:limit_exceeded, path, "string exceeds the byte limit")
  end

  defp normalize_decoded(value, _, _, _), do: {:ok, value}

  defp normalize_object_pair({key, value}, {:ok, acc}, limits, path, depth) do
    cond do
      Map.has_key?(acc, key) ->
        {:halt, Error.error(:duplicate_field, child_path(path, key), "JSON member is duplicated")}

      byte_size(key) > limits.max_string_bytes ->
        {:halt,
         Error.error(:limit_exceeded, child_path(path, key), "object key exceeds the byte limit")}

      true ->
        normalize_object_value(key, value, acc, {limits, path, depth})
    end
  end

  defp normalize_object_value(key, value, acc, {limits, path, depth}) do
    case normalize_decoded(value, limits, child_path(path, key), depth + 1) do
      {:ok, normalized} -> {:cont, {:ok, Map.put(acc, key, normalized)}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp normalize_list_item({item, index}, {:ok, acc}, limits, path, depth) do
    case normalize_decoded(item, limits, child_path(path, index), depth + 1) do
      {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp reverse_normalized({:ok, reversed}), do: {:ok, Enum.reverse(reversed)}
  defp reverse_normalized({:error, _} = error), do: error

  defp child_path(path, segment), do: Enum.concat(path, [segment])
end
