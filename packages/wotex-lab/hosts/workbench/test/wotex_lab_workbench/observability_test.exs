defmodule WotexLabWorkbench.ObservabilityTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Catalogue, Collector, Exposition}
  alias WotexLabWorkbench.Observability.{Definitions, Relay, Store}

  @promex WotexLabWorkbench.Observability.PromEx
  @name __MODULE__.Store
  @stop [:wotex, :lab, :nx, :encode, :stop]
  @measurement [:wotex, :lab, :nx, :encode, :measurement]

  test "the real PromEx public scrape matches the Lab collector, including exact boundaries" do
    promex = start_supervised!(@promex)
    start_supervised!({Relay, backend_class: :binary})
    collector = start_supervised!({Collector, backend_class: :binary})

    assert PromEx.get_metrics(@promex) == ""

    for micros <- [0, 500, 1_000, 5_000, 25_000, 99_999, 30_000_000] do
      :telemetry.execute(
        @stop,
        %{duration: System.convert_time_unit(micros, :microsecond, :native)},
        %{profile: :test, outcome: :ok, scope: "secret-scope", token: "secret-token"}
      )
    end

    :telemetry.execute(@measurement, %{rows: 8, width: 2, fill: 0.25}, %{profile: :test})
    :telemetry.execute(@measurement, %{rows: 4, width: 3, fill: 0.75}, %{profile: :test})
    :telemetry.execute(@stop, %{duration: -1}, %{profile: :test, outcome: :ok})
    :telemetry.execute(@stop, %{}, %{profile: :test, outcome: :ok})

    for outcome <- [:ok, :revision_mismatch, :unknown] do
      :telemetry.execute(
        [:wotex, :lab, :directory, :directory, :stop],
        %{duration: System.convert_time_unit(1, :millisecond, :native)},
        %{operation: :put, outcome: outcome, profile: :ets}
      )
    end

    text = PromEx.get_metrics(@promex)
    assert {:ok, parsed} = Exposition.parse(text)
    assert {:ok, expected} = Collector.snapshot(collector)
    assert parsed.series == expected.series
    refute text =~ "secret-"

    histogram = Enum.find(parsed.series, &(&1.name == "wotex_lab_nx_duration_seconds"))
    assert histogram.sample.sum == 30.131499
    assert Enum.take(histogram.sample.buckets, 3) == [{0.001, 3}, {0.005, 4}, {0.025, 5}]

    store = store_child(promex)
    assert Store.stats(store).series_used == Collector.stats(collector).series_used
    assert Store.stats(store).scrape_failures == 0
  end

  test "a fixed series budget accounts for every histogram bucket, sum and count" do
    store = start_store(11)
    histogram = metric(:nx_duration_seconds)
    counter = metric(:nx_operations_total)

    publish(histogram, 0.001)
    publish(counter, 1)
    publish(counter, 1)
    publish(counter, 1, %{profile: :http})
    publish(histogram, 0.002, %{profile: :http})

    assert %{series_budget: 11, series_used: 11, dropped_series: 2, dropped_samples: 2} =
             Store.stats(store)

    assert {:ok, snapshot} = Exposition.parse(Store.scrape(store))
    assert length(snapshot.series) == 2
    assert Enum.find(snapshot.series, &(&1.type == :counter)).sample.value == 2
    refute inspect(snapshot) =~ "http"
  end

  test "concurrent emissions aggregate without an unbounded mailbox or lost capacity" do
    # Include transient simultaneous reservations as well as the 11 retained slots.
    store = start_store(512)
    counter = metric(:nx_operations_total)
    histogram = metric(:nx_duration_seconds)

    1..32
    |> Task.async_stream(
      fn _index ->
        for _sample <- 1..100 do
          publish(counter, 1)
          publish(histogram, 0.001)
        end
      end,
      max_concurrency: 32,
      timeout: 5_000
    )
    |> Enum.each(&assert({:ok, _value} = &1))

    assert %{series_used: 11, dropped_samples: 0, invalid_samples: 0} = Store.stats(store)
    assert {:ok, snapshot} = Exposition.parse(Store.scrape(store))
    assert Enum.find(snapshot.series, &(&1.type == :counter)).sample.value == 3_200
    assert Enum.find(snapshot.series, &(&1.type == :histogram)).sample.sum == 3.2
    assert Process.info(store, :message_queue_len) == {:message_queue_len, 0}
  end

  test "unknown metric definitions, options, labels and invalid values are refused" do
    for opts <- [[unknown: 1], [:bad], %{}, [name: @name, name: @name]] do
      assert {:error, %Error{}} = Store.start_link(opts)
    end

    for opts <- [
          [metrics: [], name: @name],
          [metrics: Definitions.metrics(), name: false],
          [metrics: Definitions.metrics(), name: @name, series_budget: 0],
          [metrics: Definitions.metrics(), name: @name, series_budget: 4_097],
          [metrics: Enum.reverse(Definitions.metrics()), name: @name]
        ] do
      assert {:error, %Error{code: :invalid_metric_cohort}} = Store.start_link(opts)
    end

    for opts <- [[backend_class: :caller], [scope: "caller"], [:bad], %{}] do
      assert {:error, %Error{}} = Relay.start_link(opts)
    end

    store = start_store(64)
    counter = metric(:nx_operations_total)
    histogram = metric(:nx_duration_seconds)
    publish(counter, 2)
    publish(counter, 1, %{profile: "test"})
    publish(counter, 1, %{scope: "secret-scope"})
    publish(histogram, -1)
    publish(histogram, :nan)

    assert %{series_used: 0, invalid_samples: 5} = Store.stats(store)
    assert Store.scrape(store) == ""
    assert Store.scrape(__MODULE__.Missing) == :prom_ex_down
  end

  test "normal shutdown detaches handlers and restarting starts a fresh stream" do
    store = start_store(64)
    counter = metric(:nx_operations_total)
    generation = Store.stats(store).generation
    publish(counter, 1)
    assert Store.scrape(store) != ""

    assert Enum.any?(
             :telemetry.list_handlers(Definitions.event(counter.id)),
             &(&1.id == {Store, @name})
           )

    stop_supervised!(@name)

    refute Enum.any?(
             :telemetry.list_handlers(Definitions.event(counter.id)),
             &(&1.id == {Store, @name})
           )

    fresh = start_store(64)
    assert Store.scrape(fresh) == ""
    assert Store.stats(fresh).series_used == 0
    assert Store.stats(fresh).generation > generation
  end

  test "explicit host supervision owns both handlers and source rejection counters" do
    host = WotexLabWorkbench.Observability.Supervisor
    assert {:error, %Error{}} = host.start_link(unknown: true)
    start_supervised!(host)
    assert Process.whereis(@promex)
    assert Process.whereis(Relay)

    :telemetry.execute(@stop, %{duration: -1}, %{outcome: :ok})
    :telemetry.execute(@stop, %{duration: :nan}, %{outcome: :ok})
    :telemetry.execute(@measurement, %{rows: -1}, %{})
    :telemetry.execute(@measurement, %{fill: :nan}, %{})
    :telemetry.execute(@stop, %{}, %{})

    assert %{negative_durations: 1, invalid_samples: 3} = Relay.stats()
    assert PromEx.get_metrics(@promex) =~ "wotex_lab_nx_operations_total"
    stop_supervised!(host)
    refute Process.whereis(@promex)
    refute Process.whereis(Relay)
    refute Enum.any?(:telemetry.list_handlers(@stop), &(&1.id == Relay))
  end

  defp start_store(budget) do
    start_supervised!(%{
      id: @name,
      start:
        {Store, :start_link, [[name: @name, metrics: Definitions.metrics(), series_budget: budget]]}
    })
  end

  defp metric(id) do
    {:ok, metric} = Catalogue.fetch(id)
    metric
  end

  defp publish(metric, value, overrides \\ %{}) do
    labels =
      Map.new(metric.dimensions, fn
        :operation -> {:operation, :encode}
        :profile -> {:profile, :test}
        :backend_class -> {:backend_class, :binary}
        :outcome_class -> {:outcome_class, :ok}
      end)

    :telemetry.execute(Definitions.event(metric.id), %{value: value}, Map.merge(labels, overrides))
  end

  defp store_child(supervisor) do
    Enum.find_value(Supervisor.which_children(supervisor), fn
      {_id, pid, :worker, [Store]} -> pid
      _child -> nil
    end)
  end
end
