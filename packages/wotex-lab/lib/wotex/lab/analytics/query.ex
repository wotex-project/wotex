defmodule Wotex.Lab.Analytics.Query do
  @moduledoc """
  Closed descriptors for bounded, read-only analysis of supplied run series.

  This module performs no native work. A query selects one supplied series or
  all series, an inclusive numeric range, and a preview limit of at most 100.
  Scope is not a caller field: hosts supply only the current session's source.

  `new/2` admits known keyword options against an explicit list of available
  series names. It rejects unknown keys, reversed or non-finite bounds, unknown
  series, and oversized previews before a native analytics port receives the
  descriptor.
  """

  alias Wotex.Lab.{Error, Options}

  @defaults %{series: nil, from: nil, to: nil, limit: 100}
  @type t :: %{
          series: String.t() | nil,
          from: number() | nil,
          to: number() | nil,
          limit: pos_integer()
        }

  @doc "Admits known, unique keyword options against supplied series names."
  @spec new(term(), [String.t()]) :: {:ok, t()} | {:error, Error.t()}
  def new(opts, names) do
    with :ok <- Options.validate(opts, Map.keys(@defaults)) do
      query = Map.merge(@defaults, Map.new(opts))

      if valid?(query, names),
        do: {:ok, query},
        else:
          {:error, Error.new(:invalid_analysis_query, :analytics, "query is outside its bounds")}
    end
  end

  defp valid?(query, names) do
    (is_nil(query.series) or query.series in names) and
      bound?(query.from) and bound?(query.to) and
      (is_nil(query.from) or is_nil(query.to) or query.from <= query.to) and
      is_integer(query.limit) and query.limit in 1..100
  end

  defp bound?(nil), do: true
  defp bound?(value), do: is_number(value) and abs(value) <= 1.0e100
end
