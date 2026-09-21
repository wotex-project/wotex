defmodule Wotex.Workspace.NativeArtifact.DeliveryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeArtifact.Delivery

  test "source and prebuilt modes run only their selected operation" do
    parent = self()

    source = fn ->
      send(parent, :source)
      {:ok, :built}
    end

    prebuilt = fn ->
      send(parent, :prebuilt)
      {:ok, :retrieved}
    end

    assert {:ok, source_result} = Delivery.run(:source, source, prebuilt)
    assert source_result.selected_mode == :source
    assert source_result.actual_mode == :source
    assert source_result.value == :built
    assert_receive :source
    refute_receive :prebuilt

    assert {:ok, prebuilt_result} = Delivery.run(:prebuilt, source, prebuilt)
    assert prebuilt_result.selected_mode == :prebuilt
    assert prebuilt_result.actual_mode == :prebuilt
    assert prebuilt_result.value == :retrieved
    assert_receive :prebuilt
    refute_receive :source
  end

  test "prebuilt failure never silently invokes a source build" do
    parent = self()

    source = fn ->
      send(parent, :source)
      {:ok, :built}
    end

    prebuilt = fn -> {:error, ["unavailable"]} end

    assert {:error, failure} = Delivery.run(:prebuilt, source, prebuilt)
    assert failure.selected_mode == :prebuilt
    assert failure.actual_mode == :prebuilt
    assert failure.errors == ["unavailable"]
    refute_receive :source

    assert {:error, failure} = Delivery.run(:prefer_prebuilt, source, prebuilt)
    assert failure.selected_mode == :prefer_prebuilt
    assert failure.actual_mode == :prebuilt
    refute_receive :source
  end

  test "prefer_prebuilt falls back only when that invocation allows it" do
    source = fn -> {:ok, :built} end
    prebuilt = fn -> {:error, "not hosted"} end

    assert {:ok, result} =
             Delivery.run(:prefer_prebuilt, source, prebuilt, allow_source_fallback: true)

    assert result.selected_mode == :prefer_prebuilt
    assert result.actual_mode == :source
    assert result.value == :built
    assert result.prebuilt_errors == ["not hosted"]
  end

  test "reports both failures and rejects fallback on other modes" do
    source = fn -> {:error, ["compiler failed"]} end
    prebuilt = fn -> {:error, ["not found", "mirror failed"]} end

    assert {:error, failure} =
             Delivery.run(:prefer_prebuilt, source, prebuilt, allow_source_fallback: true)

    assert failure.actual_mode == :source

    assert failure.errors == [
             "prebuilt: not found",
             "prebuilt: mirror failed",
             "source: compiler failed"
           ]

    assert {:error, failure} =
             Delivery.run(:source, source, prebuilt, allow_source_fallback: true)

    assert failure.errors == ["source fallback is valid only with prefer_prebuilt"]
  end

  test "parses only the exact evidence mode names" do
    assert Delivery.parse("source") == {:ok, :source}
    assert Delivery.parse("prebuilt") == {:ok, :prebuilt}
    assert Delivery.parse("prefer_prebuilt") == {:ok, :prefer_prebuilt}
    assert {:error, _} = Delivery.parse("automatic")
  end
end
