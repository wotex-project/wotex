defmodule Wotex.Conformance.Input do
  @moduledoc """
  Normalizes bounded constructor input without creating atoms from external data.

  Public conformance values accept maps whose known fields may use their atom
  or string representation. `required/2` fetches a required field,
  `optional/3` applies an explicit default, and `only_keys/2` rejects unknown
  names and duplicate atom/string representations. `options/2` performs the
  corresponding validation for keyword options and rejects repeated keys.

  The caller supplies atom keys from a closed, compile-time vocabulary; this
  module converts those atoms to strings and never converts an input string to
  an atom. Failures are returned as `Wotex.Conformance.Error` values with stable
  codes and paths. The helpers validate field representation only. Semantic
  bounds, standards claims, artifact identity, and cross-field constraints
  remain with the constructor that calls them.
  """

  alias Wotex.Conformance.Error

  @doc "Fetches a required field while rejecting its absence with a structured error."
  @spec required(map(), atom()) :: {:ok, term()} | {:error, Error.t()}
  def required(input, key) when is_map(input) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(input, key) ->
        {:ok, Map.fetch!(input, key)}

      Map.has_key?(input, string_key) ->
        {:ok, Map.fetch!(input, string_key)}

      true ->
        {:error, Error.new(:missing_field, :input, "#{string_key} is required", path: [string_key])}
    end
  end

  @doc "Returns an optional field from atom or string form, or `default`."
  @spec optional(map(), atom(), term()) :: term()
  def optional(input, key, default) when is_map(input) and is_atom(key) do
    Map.get(input, key, Map.get(input, Atom.to_string(key), default))
  end

  @doc "Rejects malformed, unknown, or duplicated keyword options."
  @spec options(term(), [atom()]) :: :ok | {:error, Error.t()}
  def options(options, allowed) when is_list(options) and is_list(allowed) do
    cond do
      not Keyword.keyword?(options) ->
        invalid_options()

      duplicate_option?(options) ->
        invalid_options()

      unknown = Enum.find(Keyword.keys(options), &(&1 not in allowed)) ->
        {:error,
         Error.new(:invalid_options, :input, "options contain an unknown key",
           path: [Atom.to_string(unknown)]
         )}

      true ->
        :ok
    end
  end

  def options(_, _), do: invalid_options()

  @doc "Rejects unknown, invalid, or duplicated atom/string field representations."
  @spec only_keys(map(), [String.t()]) :: :ok | {:error, Error.t()}
  def only_keys(input, allowed) when is_map(input) and is_list(allowed) do
    normalized = Enum.map(Map.keys(input), &normalize_key/1)

    cond do
      Enum.any?(normalized, &match?(:invalid, &1)) ->
        {:error, Error.new(:invalid_field, :input, "object field names must be strings or atoms")}

      unknown = Enum.find(normalized, &(&1 not in allowed)) ->
        {:error,
         Error.new(:unknown_field, :input, "object contains an unknown field", path: [unknown])}

      length(normalized) != MapSet.size(MapSet.new(normalized)) ->
        {:error,
         Error.new(:duplicate_field, :input, "object contains duplicate field representations")}

      true ->
        :ok
    end
  end

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(_), do: :invalid

  defp duplicate_option?(options) do
    keys = Keyword.keys(options)
    length(keys) != MapSet.size(MapSet.new(keys))
  end

  defp invalid_options do
    {:error, Error.new(:invalid_options, :input, "options must be a unique keyword list")}
  end
end
