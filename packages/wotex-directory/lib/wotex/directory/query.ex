defmodule Wotex.Directory.Query do
  @moduledoc """
  Bounded Thing Description Directory query value.

  The only implemented profile is `:listing`. A query carries a positive
  `limit`, a response `format`, and an optional opaque `cursor` copied from the
  preceding page. There is no public offset: continuation is a keyset over
  identifiers, so page validity never depends on offset arithmetic over a
  time-dependent active view.
  """

  alias Wotex.Directory.{Cursor, Error}

  @enforce_keys [:profile, :limit, :format]
  defstruct [:profile, :limit, :format, :cursor]

  @type format :: :array | :collection
  @type profile :: :listing | atom()
  @type t :: %__MODULE__{
          profile: profile(),
          limit: pos_integer(),
          format: format(),
          cursor: String.t() | nil
        }

  @doc """
  Builds a bounded listing query from options and consumer limits.

  Options are `:profile`, `:limit`, `:format`, and `:cursor`. Bounds are
  `:default_limit` and `:max_limit`; an invalid bound is rejected rather than
  replaced by a default.
  """
  @spec new(keyword(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options \\ [], bounds \\ [])

  def new(options, bounds) when is_list(options) and is_list(bounds) do
    with :ok <- validate_keys(options),
         :ok <- validate_bounds(bounds),
         max_limit <- Keyword.get(bounds, :max_limit, 200),
         default <- Keyword.get(bounds, :default_limit, 50),
         query <- %__MODULE__{
           profile: Keyword.get(options, :profile, :listing),
           limit: Keyword.get(options, :limit, default),
           format: Keyword.get(options, :format, :array),
           cursor: Keyword.get(options, :cursor)
         },
         :ok <- validate(query, max_limit) do
      {:ok, query}
    end
  end

  def new(_options, _bounds), do: invalid()

  @doc "Validates a query against a maximum page limit."
  @spec validate(t(), pos_integer()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = query, max_limit)
      when is_integer(max_limit) and max_limit > 0 do
    cond do
      query.profile != :listing ->
        {:error, Error.new(:unsupported_query_profile, :listing, :list)}

      not (is_integer(query.limit) and query.limit > 0 and query.limit <= max_limit) ->
        invalid()

      query.format not in [:array, :collection] ->
        invalid()

      not valid_cursor?(query.cursor) ->
        invalid()

      true ->
        :ok
    end
  end

  def validate(_query, _max_limit), do: invalid()

  defp validate_keys(options) do
    allowed = [:profile, :limit, :format, :cursor]

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
      max_limit = Keyword.get(bounds, :max_limit, 200)

      if is_integer(default) and default > 0 and is_integer(max_limit) and max_limit > 0 and
           default <= max_limit do
        :ok
      else
        invalid()
      end
    else
      invalid()
    end
  end

  defp valid_cursor?(nil), do: true
  defp valid_cursor?(cursor), do: Cursor.valid?(cursor)

  defp invalid, do: {:error, Error.new(:invalid_request, :listing, :list)}
end
