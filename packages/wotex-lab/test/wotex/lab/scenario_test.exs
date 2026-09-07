defmodule Wotex.Lab.ScenarioTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.{Error, Scenario}

  @valid [
    id: "thermal-nx",
    title: "Temperature to proposal",
    capabilities: ["nx.encode", "nx.decode"],
    seed: 42,
    max_steps: 100
  ]

  test "accepted scenario roundtrips through portable data without atom conversion" do
    assert {:ok, scenario} = Scenario.new(@valid)
    map = Scenario.to_map(scenario)
    assert map["schema_version"] == "1.0.0"
    assert map["id"] == "thermal-nx"
    assert map["seed"] == 42
    assert map["max_steps"] == 100
    assert map["capabilities"] == ["nx.encode", "nx.decode"]
    assert Enum.all?(Map.keys(map), &is_binary/1)

    assert {:ok, decoded} =
             Wotex.ThingDescription.from_map(%{
               "@context" => Wotex.td_context_1_1(),
               "title" => "Scenario carrier",
               "security" => ["none"],
               "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
               "x-lab-scenario" => map
             })

    assert Wotex.ThingDescription.to_map(decoded)["x-lab-scenario"] == map
  end

  test "closed unique options reject malformed input and hidden execution fields" do
    for opts <- [nil, %{}, [:invalid], [id: "a", id: "b"], @valid ++ [module: System]] do
      assert {:error, %Error{code: :invalid_options, phase: :construction}} = Scenario.new(opts)
    end
  end

  test "all required fields and bounded identities are enforced" do
    for {key, _value} <- @valid do
      assert {:error, %Error{code: :invalid_scenario}} = Scenario.new(Keyword.delete(@valid, key))
    end

    changes = [
      id: "",
      id: "with space",
      id: "UPPER",
      id: String.duplicate("a", 129),
      id: <<255>>,
      title: "",
      title: <<255>>,
      title: String.duplicate("a", 257),
      capabilities: [],
      capabilities: [:atom],
      capabilities: ["nx.encode", "nx.encode"],
      capabilities: Enum.map(1..65, &"cap-#{&1}"),
      capabilities: %{},
      seed: -1,
      seed: 4_294_967_296,
      seed: 1.0,
      max_steps: 0,
      max_steps: 100_001,
      max_steps: 1.0
    ]

    for {key, value} <- changes do
      assert {:error, %Error{code: :invalid_scenario}} =
               Scenario.new(Keyword.put(@valid, key, value))
    end
  end

  test "exact upper bounds and Unicode title remain usable" do
    opts = [
      id: String.duplicate("a", 128),
      title: String.duplicate("å", 128),
      capabilities: Enum.map(1..64, &"cap-#{&1}"),
      seed: 4_294_967_295,
      max_steps: 100_000
    ]

    assert {:ok, scenario} = Scenario.new(opts)
    assert byte_size(Scenario.to_map(scenario)["title"]) == 256
  end

  test "invalid configuration is not echoed in errors" do
    assert {:error, error} = Scenario.new(@valid ++ [credential: "secret-sentinel"])
    refute inspect(error) =~ "secret-sentinel"
  end
end
