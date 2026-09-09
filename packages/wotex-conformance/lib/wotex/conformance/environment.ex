defmodule Wotex.Conformance.Environment do
  @moduledoc """
  Validation for bounded, non-sensitive conformance environment metadata.

  Environment metadata is evidence included in a report. It is not the
  operating-system environment passed to an external target.

  `validate/1` requires a string-keyed, bounded JSON object with at most eight
  levels, 128 nodes, and 1024 bytes per string. It traverses nested objects and
  arrays and rejects keys whose names indicate passwords, secrets, tokens,
  credentials, application keys, or private keys.

  The lexical screen is a fail-closed public-report boundary, not a general
  secret detector. Consumers must still supply only non-sensitive evidence such
  as runtime versions, operating-system identity, and declared capability
  settings. Process environment variables and target launch configuration are
  owned by the adapter and remain outside this reportable value.
  """

  alias Wotex.Conformance.{Error, Value}

  @sensitive_key ~r/(^|[_-])(password|passwd|secret|token|credential|api[_-]?key|private[_-]?key)($|[_-])/iu

  @doc "Validates report environment metadata and rejects keys that imply secrets."
  @spec validate(term()) :: {:ok, map()} | {:error, Error.t()}
  def validate(environment) do
    with {:ok, environment} <- Value.string_key_map(environment, "environment"),
         {:ok, _validated} <-
           Value.validate(environment,
             max_depth: 8,
             max_nodes: 128,
             max_string_bytes: 1_024
           ),
         :ok <- reject_sensitive_keys(environment, []) do
      {:ok, environment}
    end
  end

  defp reject_sensitive_keys(value, path) when is_map(value) do
    Enum.reduce_while(value, :ok, fn {key, entry}, :ok ->
      cond do
        Regex.match?(@sensitive_key, key) ->
          {:halt,
           {:error,
            Error.new(
              :sensitive_environment_key,
              :environment,
              "environment contains a sensitive key",
              path: Enum.reverse([key | path])
            )}}

        true ->
          case reject_sensitive_keys(entry, [key | path]) do
            :ok -> {:cont, :ok}
            {:error, error} -> {:halt, {:error, error}}
          end
      end
    end)
  end

  defp reject_sensitive_keys(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {entry, index}, :ok ->
      case reject_sensitive_keys(entry, [index | path]) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp reject_sensitive_keys(_value, _path), do: :ok
end
