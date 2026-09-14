defmodule Wotex.Binding.HTTP.ClientLifecycleInventoryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.HTTP
  alias Wotex.Binding.HTTP.{Subscription, Transport}
  alias Wotex.Binding.HTTP.Test.{Factory, FakeClient}

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
end
