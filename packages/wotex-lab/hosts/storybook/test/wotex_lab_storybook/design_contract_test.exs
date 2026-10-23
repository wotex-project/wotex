defmodule WotexLabStorybook.DesignContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Island.Snapshot
  alias WotexLabStorybook.DesignContract

  @moduletag :tmp_dir

  test "every live fixture retains the generated payload and canonical digest" do
    catalogue =
      :wotex_lab_storybook
      |> Application.app_dir("priv/fixtures/islands.json")
      |> File.read!()
      |> JSON.decode!()

    for {id, component} <- [
          {"reporting-chart", "chart"},
          {"data-grid", "data-grid"},
          {"navigation-tabs", "tabs"}
        ] do
      assert {:ok, snapshot} = DesignContract.fixture(id)
      assert snapshot.component == component
      assert snapshot.payload == catalogue[component]["connected"]
      assert {:ok, expected} = Snapshot.new(component, "storybook--#{id}", snapshot.payload)
      assert snapshot.payload_digest == expected.payload_digest
    end
  end

  test "unknown, missing, malformed, oversized and symbolic fixtures have no substitute", %{
    tmp_dir: root
  } do
    path = Path.join(root, "islands.json")
    assert {:error, :invalid_story_fixture} = DesignContract.fixture("unknown")
    assert {:error, :invalid_story_fixture} = DesignContract.fixture("reporting-chart", path)

    for bytes <- [
          "not JSON",
          "[]",
          "{}",
          ~s({"chart":[]}),
          ~s({"chart":{"connected":{}}}),
          String.duplicate(" ", 65_537)
        ] do
      File.write!(path, bytes)
      assert {:error, :invalid_story_fixture} = DesignContract.fixture("reporting-chart", path)
    end

    target = Application.app_dir(:wotex_lab_storybook, "priv/fixtures/islands.json")
    File.rm!(path)
    File.ln_s!(target, path)
    assert {:error, :invalid_story_fixture} = DesignContract.fixture("reporting-chart", path)
    assert {:error, :invalid_story_fixture} = DesignContract.fixture("reporting-chart", root)
  end
end
