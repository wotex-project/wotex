defmodule Wotex.Nx.Options do
  @moduledoc false

  alias Wotex.Nx.Error

  @doc false
  @spec validate(term(), [atom()], atom(), Error.phase()) :: :ok | {:error, Error.t()}
  def validate(options, allowed, code, phase) when is_list(options) and is_list(allowed) do
    cond do
      not Keyword.keyword?(options) ->
        invalid(code, phase, nil, "options must be a unique keyword list")

      duplicate_keys?(options) ->
        invalid(code, phase, nil, "option keys must be unique")

      unknown = Enum.find(Keyword.keys(options), &(&1 not in allowed)) ->
        invalid(code, phase, unknown, "option is not supported")

      true ->
        :ok
    end
  end

  def validate(_, _, code, phase) do
    invalid(code, phase, nil, "options must be a unique keyword list")
  end

  defp duplicate_keys?(options) do
    keys = Keyword.keys(options)
    length(keys) != MapSet.size(MapSet.new(keys))
  end

  defp invalid(code, phase, nil, message), do: {:error, Error.new(code, phase, message)}

  defp invalid(code, phase, field, message) do
    {:error, Error.new(code, phase, message, %{field: field})}
  end
end
