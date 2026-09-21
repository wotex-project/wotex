defmodule WotexLabWorkbench.Observability.Relay do
  @moduledoc """
  Explicit host-owned normalization of Lab events for the catalogue plugin.

  Each original event can feed several catalogue metrics. One normalized event
  per metric avoids registering duplicate Prometheus names for stop/exception
  sources. Only closed labels and one valid scalar leave the handler. Missing
  and negative durations are skipped, never emitted as zeros. This host-wide
  stream describes the Workbench Lab instance, not individual browser sessions.
  """

  use GenServer

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.Catalogue
  alias WotexLabWorkbench.Observability.Definitions

  @counters [:invalid_samples, :negative_durations]

  @doc "Starts the explicit relay; backend labels remain other unless configured."
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- Options.validate(opts, [:backend_class]) do
      if Keyword.get(opts, :backend_class, :other) in Catalogue.dimensions().backend_class do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      else
        {:error, Error.new(:invalid_backend_class, :metrics, "backend class is not admitted")}
      end
    end
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    :ok = Catalogue.validate()
    table = :ets.new(__MODULE__, [:set, :public, write_concurrency: true])
    :ets.insert(table, Enum.map(@counters, &{&1, 0}))

    index =
      Catalogue.metrics()
      |> Enum.flat_map(fn metric -> Enum.map(metric.events, &{&1, metric}) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    id = __MODULE__
    :telemetry.detach(id)
    context = %{backend_class: Keyword.get(opts, :backend_class, :other)}

    :ok =
      :telemetry.attach_many(id, Map.keys(index), &__MODULE__.handle_event/4, %{
        index: index,
        context: context,
        table: table
      })

    {:ok, %{handler: id, table: table}}
  end

  @doc "Rejected source measurements; missing measurements are not invented zeros."
  @spec stats() :: map()
  def stats, do: GenServer.call(__MODULE__, :stats, 2_000)

  @impl GenServer
  def handle_call(:stats, _, state) do
    {:reply, Map.new(@counters, &{&1, :ets.lookup_element(state.table, &1, 2)}), state}
  end

  @doc "Synchronous bounded normalization; diagnostics cannot affect the emitter."
  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(event, measurements, metadata, config) do
    Enum.each(
      Map.fetch!(config.index, event),
      &publish(&1, event, measurements, metadata, config)
    )

    :ok
  catch
    _, _ ->
      increment(config.table, :invalid_samples)
      :ok
  end

  @impl GenServer
  def terminate(_, state), do: :telemetry.detach(state.handler)

  defp publish(metric, event, measurements, metadata, config) do
    with true <- selected?(metric, event, metadata, config.context),
         {:ok, value} <- measurement(metric, measurements) do
      tags =
        Map.new(metric.dimensions, fn dimension ->
          {dimension, Catalogue.dimension_value(dimension, event, metadata, config.context)}
        end)

      :telemetry.execute(Definitions.event(metric.id), %{value: value}, tags)
    else
      {:error, counter} -> increment(config.table, counter)
      _ -> :ok
    end
  end

  defp selected?(metric, event, metadata, context) do
    Enum.all?(metric.only, fn {dimension, allowed} ->
      Catalogue.dimension_value(dimension, event, metadata, context) in allowed
    end)
  end

  defp measurement(%{measurement: nil}, _), do: {:ok, 1}

  defp measurement(%{measurement: :duration}, %{duration: duration})
       when is_integer(duration) and duration >= 0 and duration <= 1.0e100 do
    {:ok, System.convert_time_unit(duration, :native, :nanosecond) / 1_000_000_000}
  end

  defp measurement(%{measurement: :duration}, %{duration: duration})
       when is_integer(duration) and duration < 0,
       do: {:error, :negative_durations}

  defp measurement(%{measurement: :duration}, measurements) do
    if is_nil(Map.get(measurements, :duration)),
      do: :skip,
      else: {:error, :invalid_samples}
  end

  defp measurement(metric, measurements) do
    case Map.get(measurements, metric.measurement) do
      nil ->
        :skip

      value when is_number(value) and metric.type == :gauge and abs(value) <= 1.0e100 ->
        {:ok, value}

      value when is_integer(value) and value >= 0 and value <= 1.0e100 ->
        {:ok, value}

      _ ->
        {:error, :invalid_samples}
    end
  end

  defp increment(table, counter) do
    :ets.update_counter(table, counter, 1)
  catch
    _, _ -> :ok
  end
end
