defmodule WotexContinuum.Limits do
  @moduledoc """
  Resource limits applied before and after JSON decoding.
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
  @spec defaults() :: t()
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
    if Keyword.keyword?(options), do: options |> Map.new() |> new(), else: invalid_options()
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

  def new(_options), do: invalid_options()

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

    case Enum.find(fields, fn {_key, value} -> not (is_integer(value) and value > 0) end) do
      nil -> {:ok, limits}
      {key, _value} -> Error.error(:invalid_limit, [Atom.to_string(key)], "limit must be positive")
    end
  end

  defp invalid_options, do: Error.error(:invalid_type, [], "expected limit options")

  defp scan_depth(source, limits) do
    source
    |> :binary.bin_to_list()
    |> Enum.reduce_while({:ok, 0, false, false, 0}, fn byte,
                                                       {:ok, depth, in_string, escaped, string_size} ->
      scan_byte(byte, depth, in_string, escaped, string_size, limits)
    end)
    |> case do
      {:ok, _depth, _in_string, _escaped, _string_size} -> :ok
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp scan_byte(_byte, depth, true, true, string_size, _limits) do
    {:cont, {:ok, depth, true, false, string_size + 1}}
  end

  defp scan_byte(?\\, depth, true, false, string_size, _limits) do
    {:cont, {:ok, depth, true, true, string_size + 1}}
  end

  defp scan_byte(?", depth, true, false, _string_size, _limits) do
    {:cont, {:ok, depth, false, false, 0}}
  end

  defp scan_byte(_byte, depth, true, false, string_size, limits) do
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

  defp scan_byte(?", depth, false, _escaped, _string_size, _limits) do
    {:cont, {:ok, depth, true, false, 0}}
  end

  defp scan_byte(byte, depth, false, _escaped, _string_size, limits) when byte in [?{, ?[] do
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

  defp scan_byte(byte, depth, false, _escaped, _string_size, _limits) when byte in [?}, ?]] do
    {:cont, {:ok, max(depth - 1, 0), false, false, 0}}
  end

  defp scan_byte(_byte, depth, false, _escaped, _string_size, _limits) do
    {:cont, {:ok, depth, false, false, 0}}
  end

  defp normalize_decoded(_value, limits, path, depth) when depth > limits.max_depth do
    Error.error(:limit_exceeded, path, "decoded value exceeds the nesting limit")
  end

  defp normalize_decoded(%Jason.OrderedObject{values: pairs}, limits, path, depth) do
    if length(pairs) > limits.max_collection_size do
      Error.error(:limit_exceeded, path, "object exceeds the member limit")
    else
      pairs
      |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
        cond do
          Map.has_key?(acc, key) ->
            {:halt, Error.error(:duplicate_field, path ++ [key], "JSON member is duplicated")}

          byte_size(key) > limits.max_string_bytes ->
            {:halt,
             Error.error(:limit_exceeded, path ++ [key], "object key exceeds the byte limit")}

          true ->
            case normalize_decoded(value, limits, path ++ [key], depth + 1) do
              {:ok, normalized} -> {:cont, {:ok, Map.put(acc, key, normalized)}}
              {:error, _error} = error -> {:halt, error}
            end
        end
      end)
    end
  end

  defp normalize_decoded(value, limits, path, depth) when is_list(value) do
    if length(value) > limits.max_collection_size do
      Error.error(:limit_exceeded, path, "array exceeds the member limit")
    else
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
        case normalize_decoded(item, limits, path ++ [index], depth + 1) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          {:error, _error} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
        {:error, _error} = error -> error
      end
    end
  end

  defp normalize_decoded(value, limits, path, _depth) when is_binary(value) do
    if byte_size(value) <= limits.max_string_bytes,
      do: {:ok, :binary.copy(value)},
      else: Error.error(:limit_exceeded, path, "string exceeds the byte limit")
  end

  defp normalize_decoded(value, _limits, _path, _depth), do: {:ok, value}
end
