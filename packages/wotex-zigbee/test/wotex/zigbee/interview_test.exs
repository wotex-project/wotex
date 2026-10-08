defmodule Wotex.Zigbee.InterviewTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Error, Interview}

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>

  test "the finite Basic selection agrees with its pinned source profile" do
    profile =
      :json.decode(File.read!(Path.expand("../../support/profiles/zcl-basic-r8.json", __DIR__)))

    assert profile["source"]["document"] == "07-5123"
    assert profile["source"]["revision"] == "8"
    assert profile["adoption"]["cluster_id"] == 0
    assert profile["adoption"]["profile_id"] == 0x0104
    assert {:ok, request} = Interview.new(peer_ieee: @ieee, route_address: 1, source_endpoint: 1)
    assert request.basic_attributes == Enum.map(profile["adoption"]["attributes"], & &1["id"])
  end

  test "construction is inert and admits only the finite interview profile" do
    before = Process.info(self(), :messages)
    assert {:ok, request} = Interview.new(peer_ieee: @ieee, route_address: 0, source_endpoint: 240)
    assert request.basic_attributes == [0, 4, 5, 0xFFFD]
    assert request.max_endpoints == 16
    assert Process.info(self(), :messages) == before
    assert Interview.valid?(request)

    assert {:ok, request} =
             Interview.new(
               peer_ieee: @ieee,
               route_address: 0xFFF7,
               source_endpoint: 1,
               max_endpoints: 77,
               basic_attributes: [5]
             )

    assert Interview.valid?(request)

    for change <- [
          peer_ieee: <<0::64>>,
          peer_ieee: <<0xFFFFFFFFFFFFFFFF::64>>,
          peer_ieee: "invalid",
          route_address: 0xFFF8,
          route_address: -1,
          source_endpoint: 0,
          source_endpoint: 241,
          max_endpoints: 0,
          max_endpoints: 78,
          basic_attributes: [],
          basic_attributes: [5, 5],
          basic_attributes: [7],
          basic_attributes: [0, 4, 5, 0xFFFD, 7],
          basic_attributes: nil
        ] do
      refute Interview.valid?(Map.put(request, elem(change, 0), elem(change, 1)))
    end

    refute Interview.valid?(Map.put(request, :key, "credential-canary"))
    refute Interview.valid?(:invalid)

    for input <- [
          [],
          nil,
          [{1, 2}],
          [peer_ieee: @ieee, peer_ieee: @ieee],
          [key: "credential-canary"]
        ] do
      assert {:error, %Error{kind: :invalid_value} = error} = Interview.new(input)
      refute inspect(error) =~ "credential-canary"
    end
  end
end
