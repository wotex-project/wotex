defmodule Wotex.Conformance.Value do
  @moduledoc """
  Validation for bounded JSON-compatible conformance values.

  Map keys must be strings. Constructors use this module to reject unsupported
  terms, invalid UTF-8, non-finite numbers, and excessive depth or size before
  canonical encoding or target invocation.

  Limit options use the project vocabulary `:max_depth`, `:max_nodes`,
  `:max_string_bytes`, and `:max_collection_size`. An invalid limit is rejected
  with `:invalid_limit` instead of silently replaced, so a caller cannot
  believe a bound applies when it does not.

  | Option | Default | Bounds |
  | --- | --- | --- |
  | `:max_depth` | 32 | nested containers |
  | `:max_nodes` | 10,000 | JSON values including containers |
  | `:max_string_bytes` | 1 MiB | one string value or object key |
  | `:max_collection_size` | 10,000 | members of one object or array |
  """

  alias Wotex.Conformance.{Error, Input}

  @limits [:max_depth, :max_nodes, :max_string_bytes, :max_collection_size]
  @defaults %{
    max_depth: 32,
    max_nodes: 10_000,
    max_string_bytes: 1_048_576,
    max_collection_size: 10_000
  }

  @type json_value ::
          nil
          | boolean()
          | integer()
          | float()
          | String.t()
          | [json_value()]
          | %{String.t() => json_value()}

  @doc """
  Validates a JSON-compatible value against the declared limits.

  Options are `:max_depth`, `:max_nodes`, `:max_string_bytes`, and
  `:max_collection_size`.
  """
  @spec validate(term(), keyword()) :: {:ok, json_value()} | {:error, Error.t()}
  def validate(value, options \\ []) do
    with :ok <- Input.options(options, @limits),
         {:ok, limits} <- limits(options),
         {:ok, _} <- walk(value, [], 0, limits.max_nodes, limits) do
      {:ok, value}
    end
  end

  @doc "Validates a bounded identifier, with optional `:max_bytes` and `:pattern` limits."
  @spec validate_identifier(term(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def validate_identifier(value, field, options \\ []) do
    with :ok <- Input.options(options, [:max_bytes, :pattern]) do
      validate_identifier_value(
        value,
        field,
        Keyword.get(options, :max_bytes, 255),
        Keyword.get(options, :pattern, ~r/^[A-Za-z0-9][A-Za-z0-9._:\/-]*$/u)
      )
    end
  end

  @doc "Accepts a map only when every key is a string."
  @spec string_key_map(term(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def string_key_map(value, field) when is_map(value) do
    case Enum.find(Map.keys(value), &(not is_binary(&1))) do
      nil ->
        {:ok, value}

      _ ->
        {:error,
         Error.new(:invalid_map_key, :value, "#{field} keys must be strings", path: [field])}
    end
  end

  def string_key_map(_, field) do
    {:error, Error.new(:invalid_type, :value, "#{field} must be an object", path: [field])}
  end

  defp limits(options) do
    Enum.reduce_while(@limits, {:ok, @defaults}, fn key, {:ok, limits} ->
      case Keyword.fetch(options, key) do
        :error ->
          {:cont, {:ok, limits}}

        {:ok, value} when is_integer(value) and value > 0 ->
          {:cont, {:ok, Map.put(limits, key, value)}}

        {:ok, _} ->
          {:halt,
           {:error,
            Error.new(:invalid_limit, :limits, "JSON value limits must be positive integers",
              details: %{"option" => Atom.to_string(key)}
            )}}
      end
    end)
  end

  defp validate_identifier_value(value, field, max_bytes, pattern) do
    cond do
      not is_integer(max_bytes) or max_bytes <= 0 or not is_struct(pattern, Regex) ->
        {:error, Error.new(:invalid_limit, :limits, "identifier limits are invalid", path: [field])}

      not is_binary(value) ->
        {:error, Error.new(:invalid_type, :value, "#{field} must be a string", path: [field])}

      value == "" ->
        {:error, Error.new(:invalid_value, :value, "#{field} must not be empty", path: [field])}

      byte_size(value) > max_bytes ->
        {:error,
         Error.new(:limit_exceeded, :limits, "#{field} exceeds its byte limit",
           path: [field],
           details: %{"max_bytes" => max_bytes}
         )}

      not String.valid?(value) ->
        {:error,
         Error.new(:invalid_encoding, :value, "#{field} must be valid UTF-8", path: [field])}

      not Regex.match?(pattern, value) ->
        {:error,
         Error.new(:invalid_value, :value, "#{field} contains unsupported characters",
           path: [field]
         )}

      true ->
        {:ok, value}
    end
  end

  defp walk(_, path, depth, remaining, %{max_depth: max_depth}) when depth > max_depth do
    {:error,
     Error.new(:limit_exceeded, :limits, "JSON value exceeds its nesting limit",
       path: path,
       details: %{"max_depth" => max_depth, "remaining_nodes" => remaining}
     )}
  end

  defp walk(value, _, _, remaining, _)
       when is_nil(value) or is_boolean(value) or is_integer(value) do
    consume(remaining)
  end

  defp walk(value, path, _, remaining, _) when is_float(value) do
    case Jason.encode(value) do
      {:ok, _} ->
        consume(remaining)

      {:error, _} ->
        {:error, Error.new(:invalid_number, :value, "JSON numbers must be finite", path: path)}
    end
  end

  defp walk(value, path, _, remaining, %{max_string_bytes: max_bytes})
       when is_binary(value) do
    cond do
      not String.valid?(value) ->
        {:error,
         Error.new(:invalid_encoding, :value, "JSON strings must be valid UTF-8", path: path)}

      byte_size(value) > max_bytes ->
        {:error,
         Error.new(:limit_exceeded, :limits, "JSON string exceeds its byte limit",
           path: path,
           details: %{"max_string_bytes" => max_bytes}
         )}

      true ->
        consume(remaining)
    end
  end

  defp walk(value, path, depth, remaining, limits) when is_list(value) do
    with :ok <- within_collection(length(value), path, limits),
         {:ok, remaining} <- consume(remaining) do
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, remaining}, fn {entry, index}, {:ok, left} ->
        case walk(entry, path ++ [index], depth + 1, left, limits) do
          {:ok, next} -> {:cont, {:ok, next}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  defp walk(value, path, depth, remaining, limits) when is_map(value) and not is_struct(value) do
    with :ok <- within_collection(map_size(value), path, limits),
         {:ok, remaining} <- consume(remaining) do
      value
      |> Enum.sort_by(fn {key, _} -> if is_binary(key), do: key, else: inspect(key) end)
      |> Enum.reduce_while({:ok, remaining}, fn
        {key, entry}, {:ok, left} when is_binary(key) ->
          case walk(entry, path ++ [key], depth + 1, left, limits) do
            {:ok, next} -> {:cont, {:ok, next}}
            {:error, error} -> {:halt, {:error, error}}
          end

        {_, _}, _ ->
          {:halt,
           {:error,
            Error.new(:invalid_map_key, :value, "JSON object keys must be strings", path: path)}}
      end)
    end
  end

  defp walk(_, path, _, _, _) do
    {:error, Error.new(:invalid_type, :value, "value is not JSON-compatible", path: path)}
  end

  defp within_collection(size, path, %{max_collection_size: max_size}) when size > max_size do
    {:error,
     Error.new(:limit_exceeded, :limits, "JSON collection exceeds its member limit",
       path: path,
       details: %{"max_collection_size" => max_size}
     )}
  end

  defp within_collection(_, _, _), do: :ok

  defp consume(remaining) when remaining > 0, do: {:ok, remaining - 1}

  defp consume(remaining) do
    {:error,
     Error.new(:limit_exceeded, :limits, "JSON value exceeds its node limit",
       details: %{"remaining_nodes" => remaining}
     )}
  end
end
