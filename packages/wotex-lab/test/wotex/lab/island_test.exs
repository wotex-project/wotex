defmodule Wotex.Lab.IslandTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Island.{CanonicalJSON, Component, Encoder, Event, Snapshot}

  test "the registry admits only the three Lab components" do
    assert Enum.map(Component.all(), & &1["id"]) == ["chart", "data-grid", "tabs"]
    assert Component.digest() =~ ~r/\Asha256:[0-9a-f]{64}\z/
    assert {:ok, %{"story_id" => "reporting-chart"}} = Component.fetch("chart")
    assert :error = Component.fetch("unknown")
  end

  test "snapshots are canonical, bounded and reject secret-bearing or unknown props" do
    props = %{
      "label" => "Thing details",
      "tabs" => [%{"id" => "properties", "label" => "Properties", "content" => "Three values"}],
      "selected" => "properties"
    }

    assert {:ok, snapshot} =
             Snapshot.new("tabs", "session-one--tabs", props,
               revision: "7",
               capabilities: ["select"]
             )

    assert snapshot.schema == "wotex-lab-island/v1"
    assert snapshot.revision == "7"
    assert {:ok, encoded} = Snapshot.encode_inline(snapshot)
    assert byte_size(encoded) < 32 * 1_024
    assert {:ok, canonical} = Snapshot.encode(snapshot)

    assert canonical ==
             IO.iodata_to_binary(CanonicalJSON.encode(Map.from_struct(snapshot)) |> elem(1))

    assert {:error, :unknown_island_prop} = Encoder.encode("tabs", Map.put(props, "caller", true))

    assert {:error, :secret_or_invalid_island_field} =
             Encoder.encode(
               "tabs",
               put_in(props, ["tabs", Access.at(0), "access_token"], "secret")
             )
  end

  test "events and patches enforce identities, schemas and effectful command ids" do
    assert {:ok, event} =
             Event.validate("tabs", "session-one--tabs", %{
               "schema" => "wotex-lab-island-event/v1",
               "component" => "tabs",
               "instance_id" => "session-one--tabs",
               "client_revision" => "4",
               "event" => "select",
               "payload" => %{"id" => "things"}
             })

    assert event["payload"] == %{"id" => "things"}

    grid = %{
      "label" => "Things",
      "columns" => [%{"key" => "name", "label" => "Thing"}],
      "rows" => []
    }

    assert {:ok, snapshot} = Snapshot.new("data-grid", "session-one--grid", grid)

    assert {:ok, patch} =
             Snapshot.patch(snapshot, grid, "1", [
               %{"op" => "replace", "path" => "/rows", "value" => []}
             ])

    assert patch["base_revision"] == "0"

    refute match?(
             {:ok, _},
             Event.validate("data-grid", "session-one--grid", %{
               "schema" => "wotex-lab-island-event/v1",
               "component" => "data-grid",
               "instance_id" => "session-one--grid",
               "client_revision" => "0",
               "event" => "activate",
               "payload" => %{"key" => "thing-one"}
             })
           )
  end
end
