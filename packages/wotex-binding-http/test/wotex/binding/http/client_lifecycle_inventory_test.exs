defmodule Wotex.Binding.HTTP.ClientLifecycleInventoryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.HTTP
  alias Wotex.Binding.HTTP.{Subscription, Transport}
  alias Wotex.Binding.HTTP.Test.{Factory, FakeClient}

  @expected_cells [
    {"WBH-L01", ["WBH-L01-P", "WBH-L01-N1", "WBH-L01-N2"]},
    {"WBH-L02", ["WBH-L02-P", "WBH-L02-N1", "WBH-L02-N2"]},
    {"WBH-L03", ["WBH-L03-P", "WBH-L03-N1", "WBH-L03-N2"]},
    {"WBH-L04", ["WBH-L04-N1", "WBH-L04-N2", "WBH-L04-N3"]},
    {"WBH-L05", ["WBH-L05-N"]},
    {"WBH-L06", ["WBH-L06-P"]},
    {"WBH-L07", ["WBH-L07-P"]},
    {"WBH-L08", ["WBH-L08-N"]},
    {"WBH-L09", ["WBH-L09-P"]},
    {"WBH-L10", ["WBH-L10-P"]},
    {"WBH-L11", ["WBH-L11-P", "WBH-L11-N"]}
  ]

  @evidence_files [
    "test/wotex/binding/http/transport_test.exs",
    "test/wotex/binding/http/integration_test.exs",
    "test/wotex/binding/http/library_contract_test.exs",
    "test/wotex/binding/http/client_lifecycle_inventory_test.exs"
  ]

  test "the public lifecycle inventory maps every package cell to a named vector" do
    documented =
      "docs/client-lifecycle-inventory.md"
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "| WBH-L"))
      |> Enum.map(&documented_cell/1)

    assert documented == @expected_cells

    test_names =
      @evidence_files
      |> Enum.map_join("\n", &File.read!/1)
      |> then(&Regex.scan(~r/test "([^"]+)"/, &1, capture: :all_but_first))
      |> List.flatten()

    for {_, vectors} <- @expected_cells, vector <- vectors do
      assert Enum.any?(test_names, &String.contains?(&1, vector)),
             "#{vector} has no executable test"
    end
  end

  test "WBH-L11-P binding calls reuse the caller and supplied owner without spawning" do
    response = Factory.response(200, "null", [{"Content-Type", "application/json"}])
    handshake = Factory.response(200, "", [{"Content-Type", "text/event-stream"}])

    {:ok, config} =
      HTTP.config(
        client:
          {FakeClient,
           %{
             owner: self(),
             request_return: {:ok, response},
             subscribe_return: {:ok, :client_handle, handshake},
             close_return: :ok
           }}
      )

    assert :erlang.trace(self(), true, [:procs]) == 1

    try do
      assert {:ok, _} = HTTP.profile()
      assert {Transport, ^config} = HTTP.transport(config)

      request = Factory.request(:readproperty)
      assert {:ok, _} = Transport.request(request, Factory.context(), config)

      stream = Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"})

      assert {:ok, %Subscription{} = subscription} =
               Transport.subscribe(stream, self(), Factory.context(), config)

      assert :ok =
               Transport.unsubscribe(
                 subscription,
                 Factory.request(:unobserveproperty),
                 Factory.context(),
                 config
               )
    after
      :erlang.trace(self(), false, [:procs])
    end

    owner = self()
    assert_receive {:client_request, _, :credential}
    assert_receive {:client_subscribe, _, :credential, ^owner}
    assert_receive {:client_close, :client_handle}
    refute_receive {:trace, ^owner, :spawn, _, _}
  end

  defp documented_cell(line) do
    [cell, _, vectors] =
      line
      |> String.split("|", trim: true)
      |> Enum.map(&String.trim/1)

    {cell, String.split(vectors, ", ")}
  end
end
