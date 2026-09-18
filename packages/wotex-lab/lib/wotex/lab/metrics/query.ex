defmodule Wotex.Lab.Metrics.Query do
  @moduledoc """
  The admitted read-only query descriptor shared by the workbench, MCP and
  BeamLens callers.

  A query names a schema version, a server-bound instance and session scope
  that caller text cannot change, one catalogue metric id, a closed
  aggregation, finite filters over that metric's dimensions, a UTC start and
  end, a step and limits. `new/1` validates every field against the catalogue
  and applies the defaults: a 24-hour range ending now, a 5-second minimum
  step, 10,000 returned points, 1 MiB of output, a 2-second deadline and two
  concurrent queries per session. `estimate/1` admits the estimated work
  (points over the range) before anything is read, and `digest/1` is the
  SHA-256 of the canonical descriptor that every response carries.

  The descriptor says nothing about where the answer comes from; local
  history answers what ETS can answer honestly and returns `unsupported_query`
  for the rest. A `histogram_quantile` aggregation needs `:quantile`.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.Catalogue

  @schema_version "1.0.0"
  @aggregations [:last, :sum, :min, :max, :avg, :increase, :rate, :histogram_quantile]
  @default_limits %{
    range_ms: 24 * 60 * 60 * 1_000,
    min_step_ms: 5_000,
    points: 10_000,
    output_bytes: 1_048_576,
    deadline_ms: 2_000,
    concurrent: 2
  }
  @ceilings %{
    range_ms: 30 * 24 * 60 * 60 * 1_000,
    min_step_ms: 3_600_000,
    points: 100_000,
    output_bytes: 16 * 1_048_576,
    deadline_ms: 30_000,
    concurrent: 16
  }
  @floors %{min_step_ms: 1_000}
  @options ~w(scope metric aggregation filters quantile start_at end_at step_ms limits now)a

  @type aggregation :: :last | :sum | :min | :max | :avg | :increase | :rate | :histogram_quantile

  @type t :: %__MODULE__{
          schema_version: String.t(),
          scope: %{instance: String.t(), session: String.t()},
          metric: atom(),
          aggregation: aggregation(),
          filters: %{atom() => atom()},
          quantile: float() | nil,
          start_at: DateTime.t(),
          end_at: DateTime.t(),
          step_ms: pos_integer(),
          limits: %{atom() => pos_integer()}
        }

  @enforce_keys [:scope, :metric, :aggregation, :filters, :start_at, :end_at, :step_ms, :limits]
  defstruct [{:schema_version, @schema_version}, :quantile | @enforce_keys]

  @doc "The query schema version."
  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @doc "The closed aggregation enum."
  @spec aggregations() :: [aggregation()]
  def aggregations, do: @aggregations

  @doc "Default limits: range, minimum step, points, output bytes, deadline and concurrency."
  @spec default_limits() :: %{atom() => pos_integer()}
  def default_limits, do: @default_limits

  @doc "Builds a validated query from `:scope`, `:metric`, `:aggregation` and bounded options."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    with :ok <- Options.validate(opts, @options),
         {:ok, scope} <- scope(Keyword.get(opts, :scope)),
         {:ok, metric} <- Catalogue.fetch(Keyword.get(opts, :metric)),
         {:ok, aggregation} <- aggregation(Keyword.get(opts, :aggregation)),
         {:ok, filters} <- filters(Keyword.get(opts, :filters, %{}), metric),
         {:ok, quantile} <- quantile(aggregation, Keyword.get(opts, :quantile)),
         {:ok, limits} <- limits(Keyword.get(opts, :limits, %{})),
         {:ok, start_at, end_at} <- range(opts, limits),
         {:ok, step} <-
           step(Keyword.get(opts, :step_ms, default_step(start_at, end_at, limits)), limits) do
      {:ok,
       %__MODULE__{
         scope: scope,
         metric: metric.id,
         aggregation: aggregation,
         filters: filters,
         quantile: quantile,
         start_at: start_at,
         end_at: end_at,
         step_ms: step,
         limits: limits
       }}
    end
  end

  def new(_), do: {:error, error(:invalid_query, "query options must be a keyword list")}

  @doc "Revalidates a descriptor at an execution boundary; a struct is not admission."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(%__MODULE__{schema_version: @schema_version} = query) do
    query
    |> Map.from_struct()
    |> Map.delete(:schema_version)
    |> Map.to_list()
    |> new()
  rescue
    _ -> {:error, error(:invalid_query, "query descriptor is not admitted")}
  end

  def validate(_), do: {:error, error(:invalid_query, "query descriptor is not admitted")}

  @doc "Admits the estimated work: the number of points over the range against the point limit."
  @spec estimate(t()) :: {:ok, %{points: pos_integer()}} | {:error, Error.t()}
  def estimate(query) do
    with {:ok, admitted} <- validate(query), do: estimate_admitted(admitted)
  end

  defp estimate_admitted(query) do
    points = div(DateTime.diff(query.end_at, query.start_at, :millisecond), query.step_ms) + 1

    if points <= query.limits.points,
      do: {:ok, %{points: points}},
      else:
        {:error,
         error(:query_too_large, "estimated points exceed the limit",
           details: %{points: points, limit: query.limits.points}
         )}
  end

  @doc "SHA-256 of the canonical descriptor, prefixed with `sha256:`."
  @spec digest(t()) :: String.t()
  def digest(%__MODULE__{} = query) do
    canonical =
      [
        query.schema_version,
        query.scope.instance,
        query.scope.session,
        Atom.to_string(query.metric),
        Atom.to_string(query.aggregation),
        Enum.map(Enum.sort(query.filters), fn {k, v} -> "#{k}=#{v}" end),
        inspect(query.quantile),
        DateTime.to_iso8601(query.start_at),
        DateTime.to_iso8601(query.end_at),
        query.step_ms,
        Enum.sort(query.limits)
      ]
      |> :erlang.term_to_binary([:deterministic])

    "sha256:" <> (:crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower))
  end

  defp scope(%{instance: instance, session: session} = scope) when map_size(scope) == 2 do
    if Options.identifier?(instance) and Options.identifier?(session),
      do: {:ok, %{instance: instance, session: session}},
      else: {:error, error(:invalid_scope, "scope needs instance and session identifiers")}
  end

  defp scope(_), do: {:error, error(:invalid_scope, "scope needs instance and session")}

  defp aggregation(aggregation) when aggregation in @aggregations, do: {:ok, aggregation}

  defp aggregation(_),
    do: {:error, error(:invalid_aggregation, "aggregation is outside the closed enum")}

  defp filters(filters, metric) when is_map(filters) do
    enums = Catalogue.dimensions()

    valid? =
      Enum.all?(filters, fn {dimension, value} ->
        dimension in metric.dimensions and value in Map.get(enums, dimension, [])
      end)

    if valid?,
      do: {:ok, filters},
      else: {:error, error(:invalid_filter, "filters must name closed dimension values")}
  end

  defp filters(_, _), do: {:error, error(:invalid_filter, "filters must be a map")}

  defp quantile(:histogram_quantile, quantile)
       when is_float(quantile) and quantile > 0 and
              quantile < 1,
       do: {:ok, quantile}

  defp quantile(:histogram_quantile, _),
    do: {:error, error(:invalid_quantile, "histogram_quantile needs a quantile in (0, 1)")}

  defp quantile(_, nil), do: {:ok, nil}
  defp quantile(_, _), do: {:error, error(:invalid_quantile, "quantile unused")}

  defp limits(overrides) when is_map(overrides) do
    with true <- Enum.all?(overrides, fn {key, _} -> Map.has_key?(@default_limits, key) end),
         limits = Map.merge(@default_limits, overrides),
         true <- Enum.all?(limits, fn {key, value} -> positive?(value, key) end) do
      {:ok, limits}
    else
      false -> {:error, error(:invalid_limits, "limits must be positive and within ceilings")}
    end
  end

  defp limits(_), do: {:error, error(:invalid_limits, "limits must be a map")}

  defp positive?(value, key) do
    is_integer(value) and value >= Map.get(@floors, key, 1) and value <= @ceilings[key]
  end

  defp range(opts, limits) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    end_at = Keyword.get(opts, :end_at, now)
    start_at = Keyword.get(opts, :start_at, add(end_at, -limits.range_ms))

    cond do
      not (utc?(start_at) and utc?(end_at)) ->
        {:error, error(:invalid_range, "start and end must be UTC datetimes")}

      DateTime.compare(start_at, end_at) != :lt ->
        {:error, error(:invalid_range, "start must precede end")}

      DateTime.diff(end_at, start_at, :millisecond) > limits.range_ms ->
        {:error, error(:invalid_range, "range exceeds the limit")}

      true ->
        {:ok, start_at, end_at}
    end
  end

  defp add(%DateTime{} = datetime, ms), do: DateTime.add(datetime, ms, :millisecond)
  defp add(other, _), do: other

  defp utc?(%DateTime{time_zone: "Etc/UTC"}), do: true
  defp utc?(_), do: false

  # Grafana-style default: the coarsest whole-second step keeping the range within the limit.
  defp default_step(start_at, end_at, limits) do
    range = DateTime.diff(end_at, start_at, :millisecond)
    fitted = div(range, max(limits.points - 1, 1)) + 1
    max(limits.min_step_ms, div(fitted + 999, 1_000) * 1_000)
  end

  defp step(step, limits) when is_integer(step) and step >= limits.min_step_ms, do: {:ok, step}
  defp step(_, _), do: {:error, error(:invalid_step, "step is below the minimum")}

  defp error(code, message, opts \\ []), do: Error.new(code, :query, message, opts)
end
