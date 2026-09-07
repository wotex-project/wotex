defmodule Wotex.JSON.Limits do
  @moduledoc """
  Explicit resource limits for JSON admission.

  Every limit is a positive integer supplied by the caller through keyword
  options. Absent options use the documented defaults. An invalid value is
  rejected with `invalid_limit` instead of silently replaced, so a consumer
  cannot believe a limit applies when it does not.

  | Option | Default | Bounds |
  | --- | --- | --- |
  | `:max_bytes` | 1 MiB | encoded source bytes, or string payload bytes of a native map |
  | `:max_depth` | 64 | nested containers |
  | `:max_nodes` | 100,000 | JSON values including containers |
  | `:max_string_bytes` | 256 KiB | one string value or object key |
  | `:max_collection_size` | 10,000 | members of one object or array |
  """

  alias Wotex.Error

  @keys [:max_bytes, :max_depth, :max_nodes, :max_string_bytes, :max_collection_size]

  @type t :: %__MODULE__{
          max_bytes: pos_integer(),
          max_depth: pos_integer(),
          max_nodes: pos_integer(),
          max_string_bytes: pos_integer(),
          max_collection_size: pos_integer()
        }

  defstruct max_bytes: 1_048_576,
            max_depth: 64,
            max_nodes: 100_000,
            max_string_bytes: 262_144,
            max_collection_size: 10_000

  @doc "Builds limits from keyword options, rejecting any non-positive or non-integer value."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    Enum.reduce_while(@keys, {:ok, %__MODULE__{}}, fn key, {:ok, limits} ->
      case Keyword.fetch(opts, key) do
        :error ->
          {:cont, {:ok, limits}}

        {:ok, value} when is_integer(value) and value > 0 ->
          {:cont, {:ok, Map.put(limits, key, value)}}

        {:ok, value} ->
          {:halt,
           {:error,
            Error.new(:invalid_limit, :value, "limit options must be positive integers", "/", %{
              option: key,
              value: inspect(value, limit: 10, printable_limit: 40)
            })}}
      end
    end)
  end

  def new(_opts) do
    {:error, Error.new(:invalid_options, :value, "options must be a keyword list")}
  end
end
