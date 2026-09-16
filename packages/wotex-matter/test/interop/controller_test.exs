defmodule Wotex.Matter.ControllerTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter
  @moduletag :hardware

  test "a configured controller module reads its fixture and rejects an unknown path" do
    module = System.fetch_env!("WOTEX_MATTER_CLIENT_MODULE") |> String.to_existing_atom()

    fixture =
      System.fetch_env!("WOTEX_MATTER_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    path =
      Map.new(
        [:fabric_id, :node_id, :endpoint, :cluster, :member],
        &{&1, Map.fetch!(fixture, Atom.to_string(&1))}
      )

    assert {:ok, session} =
             Matter.connect([client: module, timeout: 10_000] ++ options(module, fixture))

    try do
      assert {:ok, value} = Matter.send(session, Map.put(path, :type, :read))
      assert value == Map.fetch!(fixture, "expected_value")
      unknown = Map.put(path, :member, Map.fetch!(fixture, "unsupported_member"))
      assert {:error, _} = Matter.send(session, Map.put(unknown, :type, :read))
    after
      Matter.disconnect(session)
    end
  end

  defp options(_, fixture), do: [fixture: fixture]
end
