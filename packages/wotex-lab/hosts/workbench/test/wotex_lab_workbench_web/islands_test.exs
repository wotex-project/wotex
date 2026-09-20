defmodule WotexLabWorkbenchWeb.IslandsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias WotexLabWorkbench.Chart
  alias WotexLabWorkbenchWeb.Islands

  defmodule Harness do
    @moduledoc false

    use Phoenix.Component

    import WotexLabWorkbenchWeb.Islands

    @doc false
    @spec render(map()) :: Phoenix.LiveView.Rendered.t()
    def render(assigns) do
      ~H"""
      <.chart_island id="session-fixture--chart" chart={@chart} revision={7}>
        <:fallback>
          <p id="native-fallback">Native chart remains available.</p>
        </:fallback>
      </.chart_island>
      """
    end
  end

  test "chart projections retain labels, gaps and only the public descriptor" do
    assert {:ok, chart} =
             Chart.new(
               title: "Room temperature",
               mark: "line",
               x: %{field: "time", title: "event time"},
               y: %{field: "value", title: "Cel"},
               series: [
                 %{name: "north", points: [{0, 20.0}, {1, nil}, {2, 21.0}]},
                 %{name: "south", points: [{0, 19.0}, {2, 20.0}]}
               ]
             )

    assert %{
             "title" => "Room temperature",
             "series" => [
               %{"id" => "series-0", "label" => "north"},
               %{"id" => "series-1", "label" => "south"}
             ],
             "points" => points
           } = Islands.chart_props(chart)

    assert Enum.at(points, 1) == %{
             "key" => "point-1",
             "label" => "1",
             "values" => %{"series-0" => nil, "series-1" => nil}
           }

    assert {:ok, snapshot} =
             Islands.snapshot(
               %{
                 component: "chart",
                 id: "session-fixture--chart",
                 props: Islands.chart_props(chart)
               },
               7
             )

    assert snapshot.revision == "7"
    assert snapshot.instance_id == "session-fixture--chart"
    refute inspect(snapshot) =~ "pid"
  end

  test "the HEEx boundary keeps one semantic fallback beside the ignored mount root" do
    {:ok, chart} = Chart.new(series: [%{name: "room", points: [{0, 1}]}])
    html = render_component(&Harness.render/1, chart: chart)

    assert html =~ ~s(data-pa-island="chart")
    assert html =~ ~s(phx-hook="PhoenixAssetsSvelteIsland")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(id="native-fallback")
    assert length(Regex.scan(~r/data-pa-island-mount/, html)) == 1
  end

  test "closed events reject wrong instances, revisions and unknown payload fields" do
    envelope = %{
      "schema" => "phoenix-assets-island-event/v1",
      "component" => "tabs",
      "instance_id" => "session-fixture--tabs",
      "client_revision" => "4",
      "event" => "select",
      "payload" => %{"id" => "things"}
    }

    assert {:ok, %{"event" => "select", "payload" => %{"id" => "things"}}} =
             Islands.validate_event("tabs", "session-fixture--tabs", envelope)

    assert {:error, :invalid_island_event} =
             Islands.validate_event("tabs", "session-other--tabs", envelope)

    assert {:error, :invalid_island_event} =
             Islands.validate_event(
               "tabs",
               "session-fixture--tabs",
               Map.put(envelope, "caller", true)
             )
  end

  test "identities and public row projections stay finite and session scoped" do
    assert Islands.id("session-one", "metric-samples") == "session-one--metric-samples"

    props =
      Islands.data_grid_props(
        "Samples",
        [%{key: "value", label: "Value"}],
        [%{key: "row-1", values: %{"value" => "21.5"}}]
      )

    assert props == %{
             "label" => "Samples",
             "columns" => [%{"key" => "value", "label" => "Value"}],
             "rows" => [%{"key" => "row-1", "values" => %{"value" => "21.5"}}]
           }
  end
end
