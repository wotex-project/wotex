defmodule Wotex.Directory.Query do
  @moduledoc """
  Bounded Thing Description Directory query value.

  The only implemented profile is `:listing`. A collection revision copied from
  a preceding page binds the next offset to the same collection ordering.
  """

  alias Wotex.Directory.Error

  @enforce_keys [:profile, :offset, :limit, :format]
  defstruct [:profile, :offset, :limit, :format, :collection_revision]

  @type format :: :array | :collection
  @type profile :: :listing | atom()
  @type t :: %__MODULE__{
          profile: profile(),
          offset: non_neg_integer(),
          limit: pos_integer(),
          format: format(),
          collection_revision: String.t() | nil
        }

  @spec new(keyword(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  @doc "Builds a bounded listing query from options and consumer limits."
  def new(options \\ [], bounds \\ [])

  def new(options, bounds) when is_list(options) and is_list(bounds) do
    with :ok <- validate_keys(options),
         :ok <- validate_bounds(bounds),
         maximum <- Keyword.get(bounds, :max_limit, 200),
         default <- Keyword.get(bounds, :default_limit, 50),
         query <- %__MODULE__{
           profile: Keyword.get(options, :profile, :listing),
           offset: Keyword.get(options, :offset, 0),
           limit: Keyword.get(options, :limit, default),
           format: Keyword.get(options, :format, :array),
           collection_revision: Keyword.get(options, :collection_revision)
         },
         :ok <- validate(query, maximum) do
      {:ok, query}
    end
  end

  def new(_options, _bounds), do: invalid()

  @spec validate(t(), pos_integer()) :: :ok | {:error, Error.t()}
  @doc "Validates a query against a maximum page limit."
  def validate(%__MODULE__{} = query, max_limit)
      when is_integer(max_limit) and max_limit > 0 do
    cond do
      query.profile != :listing ->
        {:error, Error.new(:unsupported_query_profile, :listing, :list)}

      not (is_integer(query.offset) and query.offset >= 0) ->
        invalid()

      not (is_integer(query.limit) and query.limit > 0 and query.limit <= max_limit) ->
        invalid()

      query.format not in [:array, :collection] ->
        invalid()

      not valid_revision?(query.collection_revision) ->
        invalid()

      true ->
        :ok
    end
  end

  def validate(_query, _maximum_limit), do: invalid()

  defp validate_keys(options) do
    allowed = [:profile, :offset, :limit, :format, :collection_revision]

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) do
      :ok
    else
      invalid()
    end
  end

  defp validate_bounds(bounds) do
    allowed = [:default_limit, :max_limit]

    if Keyword.keyword?(bounds) and Enum.all?(Keyword.keys(bounds), &(&1 in allowed)) do
      default = Keyword.get(bounds, :default_limit, 50)
      maximum = Keyword.get(bounds, :max_limit, 200)

      if is_integer(default) and default > 0 and is_integer(maximum) and maximum > 0 and
           default <= maximum do
        :ok
      else
        invalid()
      end
    else
      invalid()
    end
  end

  defp valid_revision?(nil), do: true
  defp valid_revision?(revision), do: is_binary(revision) and revision != ""

  defp invalid, do: {:error, Error.new(:invalid_request, :listing, :list)}
end
