defmodule Wotex.Matter.BridgeEndpointRegistryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.Bridge.EndpointRegistry, as: Registry
  alias Wotex.Matter.Error

  test "allocation, removal and re-add never rebind a former endpoint" do
    assert {:ok, empty} = Registry.new(max_endpoint: 5)
    assert {:ok, 3, first} = Registry.allocate(empty, "device-a")
    assert {:ok, 3, ^first} = Registry.allocate(first, "device-a")
    assert {:ok, 4, second} = Registry.allocate(first, "device-b")
    assert {:ok, "device-a"} = Registry.thing(second, 3)
    assert {:ok, 4} = Registry.endpoint(second, "device-b")

    assert {:ok, removed} = Registry.remove(second, "device-a")
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.thing(removed, 3)
    assert {:ok, 5, readded} = Registry.allocate(removed, "device-a")
    assert {:ok, 5} = Registry.endpoint(readded, "device-a")
    assert {:error, %Error{code: :endpoint_limit}} = Registry.allocate(readded, "device-c")
    assert Registry.snapshot(readded).tombstones == [3]
  end

  test "restart snapshot preserves high water mark and rejects collision or rewind" do
    {:ok, empty} = Registry.new(first_endpoint: 10, max_endpoint: 12)
    {:ok, 10, state} = Registry.allocate(empty, "source-a")
    {:ok, 11, state} = Registry.allocate(state, "source-b")
    {:ok, state} = Registry.remove(state, "source-a")
    snapshot = Registry.snapshot(state)
    assert snapshot.next_endpoint == 12
    assert snapshot.active == [{"source-b", 11}]
    assert snapshot.tombstones == [10]

    assert {:ok, restored} = Registry.restore(snapshot)
    assert Registry.snapshot(restored) == snapshot
    assert {:ok, 12, _} = Registry.allocate(restored, "source-c")

    invalid = [
      %{snapshot | next_endpoint: 11},
      %{snapshot | active: [{"source-b", 11}, {"source-b", 10}]},
      %{snapshot | active: [{"source-b", 11}, {"other", 11}]},
      %{snapshot | tombstones: [11]},
      %{snapshot | tombstones: [10, 10]},
      %{snapshot | version: 2},
      Map.put(snapshot, :unexpected, 1)
    ]

    for value <- invalid do
      assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.restore(value)
    end
  end

  test "invalid identities and bounds fail without allocation" do
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.new(first_endpoint: 2)
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.new(max_endpoint: 2)
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.new(bogus: 1)
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.new(:bad)
    assert {:ok, state} = Registry.new(max_endpoint: 3)

    for id <- ["", :not_binary, :binary.copy("x", 257)] do
      assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.allocate(state, id)
    end

    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.allocate(:bad, "id")
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.remove(state, "absent")
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.remove(:bad, "id")
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.endpoint(state, "absent")
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.endpoint(:bad, "id")
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.thing(state, 3)
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.thing(:bad, 3)
    assert {:error, %Error{code: :invalid_endpoint_catalogue}} = Registry.restore(%{})
  end

  test "a deterministic 256-device simulation survives restore and never reuses an ID" do
    {:ok, empty} = Registry.new(max_endpoint: 258)

    {state, allocated} =
      Enum.reduce(1..256, {empty, MapSet.new()}, fn number, {registry, ids} ->
        thing = "device-#{number}"
        assert {:ok, endpoint, updated} = Registry.allocate(registry, thing)
        assert MapSet.member?(ids, endpoint) == false
        {updated, MapSet.put(ids, endpoint)}
      end)

    assert MapSet.size(allocated) == 256

    assert {:ok, restored} =
             state
             |> Registry.snapshot()
             |> Registry.restore()

    assert Registry.snapshot(restored) == Registry.snapshot(state)

    {:ok, removed} = Registry.remove(restored, "device-1")
    assert {:error, %Error{code: :endpoint_limit}} = Registry.allocate(removed, "replacement")
  end
end
