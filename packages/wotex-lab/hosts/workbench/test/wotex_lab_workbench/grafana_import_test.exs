defmodule WotexLabWorkbench.GrafanaImportTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Examples.Thermal
  alias Wotex.Lab.Metrics.{GreptimeBridge, History}
  alias WotexLabWorkbench.Observability.{Durable, Panels, Relay}
  alias WotexLabWorkbench.Test.GrafanaCohort

  @moduletag :grafana
  @moduletag timeout: 600_000

  @promex WotexLabWorkbench.Observability.PromEx
  @thermal ~w(scenario_operations_total scenario_duration_seconds nx_operations_total
               nx_duration_seconds nx_rows_total nx_batch_rows nx_batch_width nx_batch_fill_ratio)

  test "every catalogue panel imports into Grafana and executes against captured Lab history" do
    cohort = GrafanaCohort.start()
    assert GrafanaCohort.version(cohort) == "13.2.2"
    start_supervised!(@promex)
    start_supervised!(Relay)
    history = start_supervised!({History, id: :grafana, instance: "workbench"})
    {:ok, options} = Durable.configure(cohort.write_url, false)

    bridge =
      start_supervised!(
        {GreptimeBridge,
         options
         |> Durable.child_options(history)
         |> Keyword.merge(name: nil, interval_ms: 3_600_000, restart: :temporary)}
      )

    started_ms = System.system_time(:millisecond)
    assert {:ok, _} = Thermal.run()
    assert {:ok, %{sequence: 1}} = GreptimeBridge.scrape_now(bridge)
    Process.sleep(2_000)
    assert {:ok, _} = Thermal.run()
    assert {:ok, %{sequence: 2}} = GreptimeBridge.scrape_now(bridge)
    assert %{exported: 2, failed: 0, rejected_permanent: 0} = await_exported(bridge, 2, 300)

    # Rates and bucket-derived quantiles need a series in both exported captures.
    captured =
      history
      |> History.snapshots()
      |> Enum.flat_map(fn %{snapshot: snapshot} -> Enum.map(snapshot.series, & &1.name) end)
      |> Enum.frequencies()

    datasource = GrafanaCohort.create_datasource(cohort)
    panels = Panels.all()
    finished_ms = System.system_time(:millisecond) + 60_000

    results =
      panels
      |> Enum.map(& &1.id)
      |> Enum.chunk_every(16)
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {ids, index} ->
        folder = GrafanaCohort.create_folder(cohort, "WoTEx Lab import #{index}")
        {:ok, exported} = Panels.dashboard(ids)
        downloaded = Jason.decode!(Jason.encode!(exported))
        response = GrafanaCohort.import(cohort, downloaded, datasource, folder)

        assert %{status: 200, body: %{"imported" => true, "uid" => uid}} = response,
               inspect(response.body)

        stored = GrafanaCohort.dashboard(cohort, uid)
        assert stored["meta"]["folderUid"] == folder
        assert length(stored["dashboard"]["panels"]) == length(ids)

        stored["dashboard"]["panels"]
        |> Enum.zip(ids)
        |> Enum.map(fn {panel, id} ->
          descriptor = Enum.find(panels, &(&1.id == id))
          [target] = panel["targets"]
          assert panel["datasource"] == %{"type" => "prometheus", "uid" => datasource}
          assert target["datasource"] == %{"type" => "prometheus", "uid" => datasource}
          assert target["expr"] == descriptor.query
          assert panel["fieldConfig"]["defaults"]["noValue"] == "unavailable"

          {descriptor, target,
           await_query(cohort, descriptor, target, captured, started_ms, finished_ms)}
        end)
      end)

    assert length(results) == length(panels)

    fed = for {descriptor, _, frames} <- results, frames != [], do: descriptor.id

    # One thermal run before each capture feeds these catalogue series in both.
    assert MapSet.subset?(MapSet.new(@thermal), MapSet.new(fed))

    for {%{type: type} = descriptor, _, frames} <- results, frame <- frames do
      case type do
        :histogram ->
          assert Enum.all?(frame.values, &(&1 > 0 and &1 <= List.last(descriptor.buckets)))

        _ ->
          assert Enum.all?(frame.values, &(&1 >= 0))
      end
    end

    {_, _, operations} =
      Enum.find(results, fn {descriptor, _, _} -> descriptor.id == "nx_operations_total" end)

    label_sets = Enum.map(operations, & &1.labels)
    assert length(label_sets) == length(Enum.uniq(label_sets))
    assert Enum.all?(label_sets, &(&1["instance"] == "workbench" and &1["profile"] == "thermal"))

    stored_values = gauge_values(history)

    for {%{type: :gauge} = descriptor, _, frames} <- results, frame <- frames do
      labels = Enum.sort(Map.drop(frame.labels, ["__name__", "instance"]))
      expected = Map.fetch!(stored_values, {descriptor.name, labels})

      assert Enum.all?(frame.values, fn value -> Enum.any?(expected, &(&1 == value)) end),
             "#{descriptor.id} changed a gauge value"
    end

    before_capture = started_ms - 3_600_000

    for {descriptor, target, frames} <- results, frames != [] do
      assert query_frames(cohort, target, before_capture, started_ms - 600_000) == [],
             "#{descriptor.id} returned values before any capture"
    end
  end

  defp await_exported(bridge, count, attempts) do
    stats = GreptimeBridge.stats(bridge)

    cond do
      stats.exported >= count -> stats
      attempts == 0 -> flunk("bridge exported #{inspect(stats)}")
      true -> Process.sleep(100) && await_exported(bridge, count, attempts - 1)
    end
  end

  # Ingestion is asynchronous at the receiver. A panel whose source series
  # were captured must eventually return finite values; every other panel must
  # answer successfully with no frame values rather than an error or zeros.
  defp await_query(cohort, descriptor, target, captured, from_ms, to_ms, attempts \\ 100) do
    frames = query_frames(cohort, target, from_ms, to_ms)
    expected? = source_captured?(descriptor, captured)

    cond do
      not expected? ->
        assert frames == [], "#{descriptor.id} returned uncaptured values #{inspect(frames)}"
        frames

      frames != [] ->
        assert Enum.all?(frames, fn frame -> Enum.all?(frame.values, &is_number/1) end)
        frames

      attempts == 0 ->
        flunk("#{descriptor.id} returned no values for captured series")

      true ->
        Process.sleep(200)
        await_query(cohort, descriptor, target, captured, from_ms, to_ms, attempts - 1)
    end
  end

  defp gauge_values(history) do
    for %{snapshot: snapshot} <- History.snapshots(history),
        %{type: :gauge, sample: %{value: value}} = series <- snapshot.series,
        is_number(value),
        reduce: %{} do
      values -> Map.update(values, {series.name, series.labels}, [value], &[value | &1])
    end
  end

  defp source_captured?(%{type: :gauge, name: name}, captured), do: Map.has_key?(captured, name)
  defp source_captured?(%{name: name}, captured), do: Map.get(captured, name, 0) >= 2

  defp query_frames(cohort, target, from_ms, to_ms) do
    response = GrafanaCohort.query(cohort, target, from_ms, to_ms)
    assert response.status == 200, inspect(response.body, limit: 20)
    assert %{"results" => %{"A" => result}} = response.body
    assert result["status"] == 200 and is_nil(result["error"]), inspect(result, limit: 20)

    result
    |> Map.get("frames", [])
    |> Enum.flat_map(fn frame ->
      fields = get_in(frame, ["schema", "fields"]) || []
      values = get_in(frame, ["data", "values"]) || []

      fields
      |> Enum.zip(values)
      |> Enum.drop(1)
      |> Enum.map(fn {field, column} ->
        %{labels: field["labels"] || %{}, values: Enum.reject(column, &is_nil/1)}
      end)
    end)
    |> Enum.reject(&(&1.values == []))
  end
end
