defmodule Wotex.Conformance.Input do
  @moduledoc false

  alias Wotex.Conformance.Error

  @spec required(map(), atom()) :: {:ok, term()} | {:error, Error.t()}
  def required(input, key) when is_map(input) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(input, key) -> {:ok, Map.fetch!(input, key)}
      Map.has_key?(input, string_key) -> {:ok, Map.fetch!(input, string_key)}
      true -> {:error, Error.new(:missing_field, "#{string_key} is required", path: [string_key])}
    end
  end

  @spec optional(map(), atom(), term()) :: term()
  def optional(input, key, default) when is_map(input) and is_atom(key) do
    Map.get(input, key, Map.get(input, Atom.to_string(key), default))
  end

  @spec only_keys(map(), [String.t()]) :: :ok | {:error, Error.t()}
  def only_keys(input, allowed) when is_map(input) and is_list(allowed) do
    normalized = Enum.map(Map.keys(input), &normalize_key/1)

    cond do
      Enum.any?(normalized, &match?(:invalid, &1)) ->
        {:error, Error.new(:invalid_field, "object field names must be strings or atoms")}

      unknown = Enum.find(normalized, &(&1 not in allowed)) ->
        {:error, Error.new(:unknown_field, "object contains an unknown field", path: [unknown])}

      length(normalized) != MapSet.size(MapSet.new(normalized)) ->
        {:error, Error.new(:duplicate_field, "object contains duplicate field representations")}

      true ->
        :ok
    end
  end

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(_key), do: :invalid
end
