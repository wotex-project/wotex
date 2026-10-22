defmodule Wotex.Lab.CanvasIslandTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Island.Encoder

  test "Run captures are a distinct closed pin kind with bounded original values" do
    pin = %{
      "kind" => "run",
      "id" => "pin-run-a",
      "title" => "Run capture",
      "run_id" => "run-1",
      "record_digest" => "sha256:" <> String.duplicate("a", 64),
      "chart_index" => 0,
      "source_mode" => "fixture",
      "state" => "Captured · completed",
      "started_at" => "2026-10-22T00:00:00.123456Z",
      "unit" => "°C",
      "mark" => "area",
      "outcome" => %{
        "label" => "Proposed target",
        "value" => "22.000",
        "unit" => "°C",
        "note" => "Inert proposal"
      },
      "series" => [%{"name" => "temperature", "points" => [[0, -4], [1, nil], [2, 8]]}],
      "x" => 0,
      "y" => 0,
      "width" => 360,
      "height" => 340
    }

    payload = Map.put(props(), "pins", [pin])
    assert {:ok, ^payload} = Encoder.encode("canvas", payload)

    full =
      put_in(payload, ["pins", Access.at(0), "series"], [
        %{"name" => "temperature", "points" => for(n <- 1..512, do: [n, -n])}
      ])

    assert {:ok, ^full} = Encoder.encode("canvas", full)

    for {field, value} <- [
          {"chart_index", 8},
          {"chart_index", 1.0},
          {"started_at", "2026-02-31T00:00:00Z"},
          {"started_at", "2026-10-22T00:00:00+01:00"},
          {"mark", "script"},
          {"record_digest", "other"},
          {"outcome", %{"value" => 2}},
          {"metric", "nx_batch_rows"},
          {"series", [%{"name" => "temperature", "points" => for(n <- 1..513, do: [n, n])}]}
        ] do
      bad = update_in(payload, ["pins", Access.at(0)], &Map.put(&1, field, value))
      assert {:error, _} = Encoder.encode("canvas", bad)
    end
  end

  test "canvas payloads retain missing samples and bounded saved presentation" do
    props = props()
    assert {:ok, ^props} = Encoder.encode("canvas", props)
    assert {:ok, _} = Encoder.encode("canvas", %{"label" => "Empty", "nodes" => [], "edges" => []})
  end

  test "nested pin input refuses numerical overflow, ambiguous identities and extra data" do
    for {field, value} <- [
          {"id", "thermostat"},
          {"metric", "caller()"},
          {"title", String.duplicate("字", 43)},
          {"auto_refresh", "true"},
          {"range", "30d"},
          {"end_ms", 9_007_199_254_740_992},
          {"x", 20_001},
          {"height", 601},
          {"width", 299},
          {"series", nil},
          {"series", [%{"name" => "room", "points" => [[0, "missing"]]}]},
          {"series", [%{"name" => "room", "points" => [[0, 1.0e101]]}]},
          {"series", [%{"name" => "room", "points" => [[0]]}]},
          {"series", [%{"name" => "room", "points" => [], "source" => "extra"}]},
          {"series", List.duplicate(%{"name" => "room", "points" => []}, 2)},
          {"series", [nil]}
        ] do
      malformed = update_in(props(), ["pins", Access.at(0)], &Map.put(&1, field, value))
      assert {:error, _} = Encoder.encode("canvas", malformed)
    end

    for malformed <- [
          put_in(props(), ["pins", Access.at(0), "extra"], true),
          put_in(props(), ["pins"], List.duplicate(pin(), 17)),
          put_in(props(), ["pins"], [nil]),
          put_in(props(), ["view"], [%{"x" => 0, "y" => 0, "zoom" => 0}]),
          put_in(props(), ["view"], [%{"x" => 0, "y" => 0, "zoom" => 1, "extra" => true}]),
          put_in(props(), ["view"], [nil]),
          put_in(props(), ["layout_revision"], "01")
        ] do
      assert {:error, _} = Encoder.encode("canvas", malformed)
    end
  end

  defp props do
    %{
      "label" => "Room",
      "nodes" => [
        %{
          "id" => "thermostat",
          "kind" => "thing",
          "title" => "Thermostat",
          "identity" => "urn:test:thermostat",
          "value" => "21.5",
          "unit" => "°C",
          "status" => "Read",
          "detail" => "",
          "x" => 0,
          "y" => 100
        }
      ],
      "edges" => [],
      "pins" => [pin()],
      "view" => [%{"x" => -100, "y" => 50, "zoom" => 0.75}],
      "layout_revision" => "1"
    }
  end

  defp pin do
    %{
      "id" => "pin-rows",
      "title" => "Rows",
      "metric" => "nx_batch_rows",
      "source" => "Room history",
      "range" => "5m",
      "unit" => "rows",
      "aggregation" => "last value per step",
      "state" => "Paused",
      "auto_refresh" => false,
      "end_ms" => 1_799_000_300_000,
      "x" => 100,
      "y" => 200,
      "width" => 360,
      "height" => 280,
      "series" => [%{"name" => "room", "points" => [[-20, -4], [-15, nil], [-10, 2]]}]
    }
  end
end
