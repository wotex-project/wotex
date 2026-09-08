defmodule WotexLabWorkbench.Metrics do
  @moduledoc """
  A bounded, host-wide ring of Lab telemetry samples.

  The host attaches one `:telemetry` handler for every Lab component and
  operation at start. The handler performs two ETS operations in the emitter:
  an atomic sequence increment and an insert into the slot the sequence maps
  to, so the ring never grows past its capacity and overwrites its oldest
  sample instead of queueing. `query/2` reads a bounded window and reports
  freshness and how many samples were overwritten since the window's oldest
  surviving sample; an empty ring is reported as unavailable, never as zero
  measurements. Only allowlisted Lab metadata reaches the ring, so no Thing
  id, prompt, payload or principal becomes a label. This is not PromEx,
  GreptimeDB or a durable store.
  """

  use GenServer

  alias Wotex.Lab.Error
  alias Wotex.Lab.Telemetry

  @prefix [:wotex, :lab]
  @components Telemetry.components()
  @operations Telemetry.operations()
  @events [:stop, :exception, :measurement]
  @max_limit 2_000
  @max_window_ms 86_400_000
  @max_scope_bytes 64
  @query_keys ~w(component operation scope window_ms limit)a

  @type sample :: %{
          sequence: pos_integer(),
          at: integer(),
          component: atom(),
          operation: atom(),
          event: atom(),
          duration_ms: number() | nil,
          measurements: map(),
          outcome: atom() | nil,
          profile: atom() | String.t() | nil,
          scope: String.t() | nil
        }

  @doc "Starts the ring with `:capacity` (samples) and an optional `:name`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Reads the newest samples that match the filters.

  Options: `:component`, `:operation`, `:scope`, `:window_ms` (default five
  minutes, ceiling 24 hours) and `:limit` (default and ceiling #{@max_limit}).
  Returns `{:error, :unavailable}` when nothing has been collected.
  """
  @spec query(GenServer.server(), keyword()) ::
          {:ok, map()} | {:error, :unavailable | Error.t()}
  def query(server \\ __MODULE__, opts)

  def query(server, opts) when is_list(opts) do
    with {:ok, filters} <- admit_query(opts) do
      GenServer.call(server, {:query, filters})
    end
  end

  def query(_server, _opts),
    do: {:error, Error.new(:invalid_query, :metrics, "query options must be a keyword list")}

  @doc "Emits one host-owned, session-scoped measurement synchronously."
  @spec record(String.t(), Telemetry.component(), Telemetry.operation(), map(), map()) :: :ok
  def record(scope, component, operation, measurements, metadata \\ %{})
      when is_binary(scope) and byte_size(scope) <= @max_scope_bytes and
             component in @components and operation in @operations and
             is_map(measurements) and is_map(metadata) do
    :telemetry.execute(
      @prefix ++ [component, operation, :measurement],
      Map.new(measurements, fn {key, value} -> {key, value} end),
      metadata |> Map.take([:outcome, :profile]) |> Map.put(:scope, scope)
    )
  end

  @doc "The telemetry handler; runs synchronously in the emitting process."
  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(@prefix ++ [component, operation, event], measurements, metadata, config) do
    if :ets.info(config.table) == :undefined do
      :telemetry.detach(config.handler_id)
      :ok
    else
      write_sample(config, component, operation, event, measurements, metadata)
    end
  rescue
    ArgumentError ->
      :telemetry.detach(config.handler_id)
      :ok
  end

  @impl GenServer
  def init(opts) do
    capacity = Keyword.fetch!(opts, :capacity)
    true = is_integer(capacity) and capacity in 16..65_536
    table = :ets.new(__MODULE__, [:set, :public, write_concurrency: true])
    handler_id = {__MODULE__, self()}

    events =
      for component <- Telemetry.components(),
          operation <- Telemetry.operations(),
          event <- @events,
          do: @prefix ++ [component, operation, event]

    :ok =
      :telemetry.attach_many(handler_id, events, &__MODULE__.handle_event/4, %{
        table: table,
        capacity: capacity,
        handler_id: handler_id
      })

    {:ok, %{table: table, capacity: capacity, handler_id: handler_id}}
  end

  @impl GenServer
  def handle_call({:query, filters}, _from, state) do
    latest = :ets.lookup_element(state.table, :sequence, 2, 0)

    if latest == 0 do
      {:reply, {:error, :unavailable}, state}
    else
      result = read(state, filters, latest)
      reply = if result.samples == [], do: {:error, :unavailable}, else: {:ok, result}
      {:reply, reply, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    :telemetry.detach(state.handler_id)
    :ok
  end

  defp read(state, filters, latest) do
    now = System.system_time(:millisecond)
    window = Map.get(filters, :window_ms, 300_000)
    limit = filters |> Map.get(:limit, @max_limit) |> min(@max_limit) |> max(1)
    oldest_kept = max(latest - state.capacity + 1, 1)

    samples =
      state.table
      |> :ets.tab2list()
      |> Enum.flat_map(fn
        {slot, sample} when is_integer(slot) -> [sample]
        _sequence -> []
      end)
      |> Enum.filter(&(&1.at >= now - window and matches?(&1, filters)))
      |> Enum.sort_by(& &1.sequence, :desc)
      |> Enum.take(limit)
      |> Enum.reverse()

    %{
      source: :live,
      samples: samples,
      unit: "ms",
      interval: %{from: now - window, to: now},
      watermark: latest,
      freshness_ms: freshness(samples, now),
      loss: %{
        overwritten: oldest_kept - 1,
        capacity: state.capacity,
        retained: latest - oldest_kept + 1
      },
      truncated: length(samples) == limit
    }
  end

  defp matches?(sample, filters) do
    Enum.all?([:component, :operation, :scope], fn key ->
      case Map.get(filters, key) do
        nil -> true
        value -> Map.fetch!(sample, key) == value
      end
    end)
  end

  defp freshness([], _now), do: nil
  defp freshness(samples, now), do: now - Enum.max_by(samples, & &1.at).at

  defp duration(%{duration: native}) when is_integer(native),
    do: System.convert_time_unit(native, :native, :microsecond) / 1_000

  defp duration(_measurements), do: nil

  defp write_sample(config, component, operation, event, measurements, metadata) do
    sequence = :ets.update_counter(config.table, :sequence, {2, 1}, {:sequence, 0})

    sample = %{
      sequence: sequence,
      at: System.system_time(:millisecond),
      component: component,
      operation: operation,
      event: event,
      duration_ms: duration(measurements),
      measurements: measurements |> Map.drop([:duration, :monotonic_time, :system_time]),
      outcome: Map.get(metadata, :outcome),
      profile: Map.get(metadata, :profile),
      scope: scope(metadata)
    }

    true = :ets.insert(config.table, {rem(sequence, config.capacity), sample})
    :ok
  end

  defp admit_query(opts) do
    if Keyword.keyword?(opts) do
      admit_keyword_query(opts)
    else
      {:error, Error.new(:invalid_query, :metrics, "query options must be unique keywords")}
    end
  end

  defp admit_keyword_query(opts) do
    keys = Keyword.keys(opts)
    filters = Map.new(opts)

    cond do
      length(keys) != length(Enum.uniq(keys)) ->
        {:error, Error.new(:invalid_query, :metrics, "query options must be unique keywords")}

      Enum.any?(keys, &(&1 not in @query_keys)) ->
        {:error, Error.new(:invalid_query, :metrics, "query option is not admitted")}

      not member_or_nil?(filters[:component], @components) ->
        {:error, Error.new(:invalid_query, :metrics, "component is not admitted")}

      not member_or_nil?(filters[:operation], @operations) ->
        {:error, Error.new(:invalid_query, :metrics, "operation is not admitted")}

      not scope_or_nil?(filters[:scope]) ->
        {:error, Error.new(:invalid_query, :metrics, "scope is malformed")}

      not integer_bound?(Map.get(filters, :window_ms, 300_000), 1, @max_window_ms) ->
        {:error, Error.new(:invalid_query, :metrics, "window is outside its bounds")}

      not integer_bound?(Map.get(filters, :limit, @max_limit), 1, @max_limit) ->
        {:error, Error.new(:invalid_query, :metrics, "limit is outside its bounds")}

      true ->
        {:ok, filters}
    end
  end

  defp member_or_nil?(nil, _allowed), do: true
  defp member_or_nil?(value, allowed), do: value in allowed
  defp scope_or_nil?(nil), do: true
  defp scope_or_nil?(value), do: is_binary(value) and byte_size(value) <= @max_scope_bytes
  defp integer_bound?(value, minimum, maximum), do: is_integer(value) and value in minimum..maximum

  defp scope(%{scope: scope}) when is_binary(scope) and byte_size(scope) <= @max_scope_bytes,
    do: scope

  defp scope(_metadata), do: nil
end
