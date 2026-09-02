defmodule Wotex.Conformance.Environment do
  @moduledoc false

  alias Wotex.Conformance.{Error, Value}

  @sensitive_key ~r/(^|[_-])(password|passwd|secret|token|credential|api[_-]?key|private[_-]?key)($|[_-])/iu

  @spec validate(term()) :: {:ok, map()} | {:error, Error.t()}
  def validate(environment) do
    with {:ok, environment} <- Value.string_key_map(environment, "environment"),
         {:ok, _validated} <-
           Value.validate(environment,
             max_depth: 8,
             max_entries: 128,
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
            Error.new(:sensitive_environment_key, "environment contains a sensitive key",
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
