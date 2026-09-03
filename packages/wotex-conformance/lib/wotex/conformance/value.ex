defmodule Wotex.Conformance.Value do
  @moduledoc """
  Validation for bounded JSON-compatible conformance values.

  Map keys must be strings. Constructors use this module to reject unsupported
  terms, invalid UTF-8, non-finite numbers, and excessive depth or size before
  canonical encoding or target invocation.
  """

  alias Wotex.Conformance.Error

  @default_max_depth 32
  @default_max_entries 10_000
  @default_max_string_bytes 1_048_576

  @type json_value ::
          nil
          | boolean()
          | integer()
          | float()
          | String.t()
          | [json_value()]
          | %{String.t() => json_value()}

  @doc """
  Validates a JSON-compatible value against depth, entry, and string limits.

  Options are `:max_depth`, `:max_entries`, and `:max_string_bytes`.
  """
  @spec validate(term(), keyword()) :: {:ok, json_value()} | {:error, Error.t()}
  def validate(value, options \\ []) do
    limits = %{
      max_depth: Keyword.get(options, :max_depth, @default_max_depth),
      max_entries: Keyword.get(options, :max_entries, @default_max_entries),
      max_string_bytes: Keyword.get(options, :max_string_bytes, @default_max_string_bytes)
    }

    with :ok <- validate_limits(limits),
         {:ok, _remaining} <- walk(value, [], 0, limits.max_entries, limits) do
      {:ok, value}
    end
  end

  @doc "Validates a bounded identifier, with optional `:max_bytes` and `:pattern` limits."
  @spec validate_identifier(term(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def validate_identifier(value, field, options \\ []) do
    max_bytes = Keyword.get(options, :max_bytes, 255)
    pattern = Keyword.get(options, :pattern, ~r/^[A-Za-z0-9][A-Za-z0-9._:\/-]*$/u)

    cond do
      not is_binary(value) ->
        {:error, Error.new(:invalid_type, "#{field} must be a string", path: [field])}

      value == "" ->
        {:error, Error.new(:invalid_value, "#{field} must not be empty", path: [field])}

      byte_size(value) > max_bytes ->
        {:error,
         Error.new(:limit_exceeded, "#{field} exceeds its byte limit",
           path: [field],
           details: %{"max_bytes" => max_bytes}
         )}

      not String.valid?(value) ->
        {:error, Error.new(:invalid_encoding, "#{field} must be valid UTF-8", path: [field])}

      not Regex.match?(pattern, value) ->
        {:error,
         Error.new(:invalid_value, "#{field} contains unsupported characters", path: [field])}

      true ->
        {:ok, value}
    end
  end

  @doc "Accepts a map only when every key is a string."
  @spec string_key_map(term(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def string_key_map(value, field) when is_map(value) do
    case Enum.find(Map.keys(value), &(not is_binary(&1))) do
      nil -> {:ok, value}
      _key -> {:error, Error.new(:invalid_map_key, "#{field} keys must be strings", path: [field])}
    end
  end

  def string_key_map(_value, field) do
    {:error, Error.new(:invalid_type, "#{field} must be an object", path: [field])}
  end

  defp validate_limits(limits) do
    if Enum.all?(limits, fn {_key, value} -> is_integer(value) and value > 0 end) do
      :ok
    else
      {:error, Error.new(:invalid_limit, "JSON value limits must be positive integers")}
    end
  end

  defp walk(_value, path, depth, remaining, %{max_depth: max_depth}) when depth > max_depth do
    {:error,
     Error.new(:limit_exceeded, "JSON value exceeds its nesting limit",
       path: Enum.reverse(path),
       details: %{"max_depth" => max_depth, "remaining_entries" => remaining}
     )}
  end

  defp walk(value, _path, _depth, remaining, _limits)
       when is_nil(value) or is_boolean(value) or is_integer(value) do
    consume(remaining)
  end

  defp walk(value, path, _depth, remaining, _limits) when is_float(value) do
    case Jason.encode(value) do
      {:ok, _encoded} ->
        consume(remaining)

      {:error, _reason} ->
        {:error,
         Error.new(:invalid_number, "JSON numbers must be finite", path: Enum.reverse(path))}
    end
  end

  defp walk(value, path, _depth, remaining, %{max_string_bytes: max_bytes})
       when is_binary(value) do
    cond do
      not String.valid?(value) ->
        {:error,
         Error.new(:invalid_encoding, "JSON strings must be valid UTF-8", path: Enum.reverse(path))}

      byte_size(value) > max_bytes ->
        {:error,
         Error.new(:limit_exceeded, "JSON string exceeds its byte limit",
           path: Enum.reverse(path),
           details: %{"max_bytes" => max_bytes}
         )}

      true ->
        consume(remaining)
    end
  end

  defp walk(value, path, depth, remaining, limits) when is_list(value) do
    with {:ok, remaining} <- consume(remaining) do
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, remaining}, fn {entry, index}, {:ok, left} ->
        case walk(entry, [index | path], depth + 1, left, limits) do
          {:ok, next} -> {:cont, {:ok, next}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  defp walk(value, path, depth, remaining, limits) when is_map(value) and not is_struct(value) do
    with {:ok, remaining} <- consume(remaining) do
      value
      |> Enum.sort_by(fn {key, _entry} -> if is_binary(key), do: key, else: inspect(key) end)
      |> Enum.reduce_while({:ok, remaining}, fn
        {key, entry}, {:ok, left} when is_binary(key) ->
          case walk(entry, [key | path], depth + 1, left, limits) do
            {:ok, next} -> {:cont, {:ok, next}}
            {:error, error} -> {:halt, {:error, error}}
          end

        {_key, _entry}, _acc ->
          {:halt,
           {:error,
            Error.new(:invalid_map_key, "JSON object keys must be strings",
              path: Enum.reverse(path)
            )}}
      end)
    end
  end

  defp walk(_value, path, _depth, _remaining, _limits) do
    {:error, Error.new(:invalid_type, "value is not JSON-compatible", path: Enum.reverse(path))}
  end

  defp consume(remaining) when remaining > 0, do: {:ok, remaining - 1}

  defp consume(_remaining) do
    {:error, Error.new(:limit_exceeded, "JSON value exceeds its entry limit")}
  end
end
