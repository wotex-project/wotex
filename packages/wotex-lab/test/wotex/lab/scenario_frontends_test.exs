defmodule Wotex.Lab.ScenarioFrontendsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.{Error, Scenario}
  alias Wotex.Lab.Graph.Descriptors
  alias Wotex.Lab.MCP.Server
  alias Wotex.Lab.Test.CookbookRunner

  setup do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous) end)
  end

  test "the admitted descriptors are complete, valid and bound to the catalogue" do
    admitted = Scenario.admitted()
    descriptors = Descriptors.scenarios()

    assert Enum.map(admitted, &Scenario.to_map(&1)["id"]) == Enum.map(descriptors, & &1.id)

    for {scenario, descriptor} <- Enum.zip(admitted, descriptors) do
      map = Scenario.to_map(scenario)
      assert {:ok, ^scenario} = Scenario.revalidate(scenario)
      assert map["seed"] == 1
      assert map["max_steps"] == max(length(descriptor.steps), 1)
      assert map["capabilities"] == descriptor.capabilities
      assert {:ok, ^scenario} = Scenario.fetch_admitted(map["id"])
    end

    assert {:error, %Error{code: :unknown_scenario, phase: :construction}} =
             Scenario.fetch_admitted("not-admitted")

    for malformed <- [nil, :smart_room, String.duplicate("a", 129)] do
      assert {:error, %Error{code: :invalid_scenario_id}} = Scenario.fetch_admitted(malformed)
    end
  end

  test "the CLI and the MCP resource return identical admitted descriptors" do
    expected = %{"scenarios" => Enum.map(Scenario.admitted(), &Scenario.to_map/1)}

    Mix.Tasks.Wotex.Lab.Scenarios.run([])
    assert_received {:mix_shell, :info, [cli]}
    assert {:ok, ^expected} = Wotex.JSON.decode(cli)

    state = session()

    {reply, _} =
      Server.handle(state, request(2, "resources/read", %{"uri" => "wotex-lab://scenarios"}))

    assert [%{"mimeType" => "application/json", "text" => text}] = reply["result"]["contents"]
    assert text == cli
    assert {:ok, ^expected} = Wotex.JSON.decode(text)

    for descriptor <- expected["scenarios"] do
      Mix.Tasks.Wotex.Lab.Scenarios.run([descriptor["id"]])
      assert_received {:mix_shell, :info, [single]}
      assert {:ok, ^descriptor} = Wotex.JSON.decode(single)
    end
  end

  test "the CLI refuses unknown, malformed and extra arguments without output" do
    assert_raise Mix.Error, "unknown_scenario: scenario is not admitted", fn ->
      Mix.Tasks.Wotex.Lab.Scenarios.run(["not-admitted"])
    end

    assert_raise Mix.Error, "invalid_scenario_id: scenario id is malformed", fn ->
      Mix.Tasks.Wotex.Lab.Scenarios.run([String.duplicate("a", 129)])
    end

    assert_raise Mix.Error, ~r/usage/, fn ->
      Mix.Tasks.Wotex.Lab.Scenarios.run(["smart-room", "extra"])
    end

    refute_received {:mix_shell, :info, _}
  end

  @tag :integration
  test "the Livebook cookbook lists the same admitted descriptor as the CLI" do
    assert {:ok, outcome} = CookbookRunner.run("nerves-and-mcp")
    assert outcome.leaked == 0

    Mix.Tasks.Wotex.Lab.Scenarios.run(["nerves-and-mcp"])
    assert_received {:mix_shell, :info, [cli]}
    assert {:ok, descriptor} = Wotex.JSON.decode(cli)
    assert Keyword.fetch!(outcome.binding, :descriptor) == descriptor
  end

  defp request(id, method, params),
    do: %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

  defp session do
    {:ok, state} = Server.new([])

    {_, state} =
      Server.handle(state, request(1, "initialize", %{"protocolVersion" => "2025-11-25"}))

    {nil, state} =
      Server.handle(state, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    state
  end
end
