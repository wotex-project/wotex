defmodule WotexLabWorkbench.MetricPanelsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.Catalogue
  alias WotexLabWorkbench.Observability.{Definitions, Panels}

  test "every definition, descriptor and dashboard query comes from the same catalogue" do
    assert length(Panels.all()) == length(Catalogue.metrics())

    for {metric, definition, panel} <-
          Enum.zip([Catalogue.metrics(), Definitions.metrics(), Panels.all()]) do
      assert panel.name == metric.name
      assert panel.unit == metric.unit
      assert panel.scope == metric.scope
      assert panel.dimensions == metric.dimensions
      assert panel.buckets == metric.buckets
      assert definition.name == [String.to_existing_atom(metric.name)]
      assert definition.tags == panel.dimensions
      assert definition.reporter_options[:buckets] == panel.buckets
      assert definition.reporter_options[:scope] == panel.scope

      {:ok, dashboard} = Panels.dashboard([panel.id])
      [exported] = dashboard["panels"]
      assert hd(exported.targets).expr == panel.query
      assert exported.fieldConfig.defaults.noValue == "unavailable"
      assert exported.fieldConfig.defaults.custom.spanNulls == false
      refute panel.query =~ " or "
      refute panel.query =~ "avg("

      case metric.type do
        :histogram ->
          assert panel.query == "histogram_quantile(0.95, rate(#{metric.name}_bucket[5m]))"
          assert panel.display_unit == Atom.to_string(metric.unit)

        :counter ->
          assert panel.query == "rate(#{metric.name}[5m])"
          assert panel.display_unit == "#{metric.unit}/second"

        :gauge ->
          assert panel.query == metric.name
          assert panel.display_unit == Atom.to_string(metric.unit)
      end
    end
  end

  test "dashboard composition admits only bounded known IDs, never caller code" do
    for ids <- [
          [],
          %{},
          "nx_duration_seconds",
          [:nx_duration_seconds],
          ["__proto__"],
          ["${caller}"],
          ["nx_duration_seconds", "nx_duration_seconds"],
          List.duplicate("nx_duration_seconds", 17)
        ] do
      assert {:error, %Error{code: :invalid_panels}} = Panels.dashboard(ids)
    end

    assert {:ok, dashboard} = Panels.dashboard()
    assert length(dashboard["panels"]) == 4
    assert dashboard["refresh"] == ""
    assert dashboard["editable"] == false
    assert dashboard["links"] == []
    json = Jason.encode!(dashboard)
    assert byte_size(json) < 65_536
    assert Jason.decode!(json)["panels"] |> length() == 4
  end
end
