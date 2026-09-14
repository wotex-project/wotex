defmodule Wotex.Binding.HTTP.IntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.HTTP
  alias Wotex.Binding.HTTP.Request
  alias Wotex.Binding.HTTP.SSE.Event
  alias Wotex.Binding.HTTP.Test.{FakeClient, FakeCredentials}
  alias Wotex.Runtime.{ConsumedThing, Context, Error, Result, Subscription}

  test "ConsumedThing executes a one-shot interaction through the HTTP binding" do
    response = response(200, "21", [{"Content-Type", "application/json"}])
    consumed = consumed_thing(%{request_return: {:ok, response}})
    context = Context.new!(request_id: "integration-request")

    assert {:ok, %Result{payload: 21, operation: :readproperty, status: :ok} = result} =
             ConsumedThing.read_property(consumed, "temperature", context)

    assert result.metadata.http.status == 200
    assert_receive {:credential_resolve, %{names: ["nosec"]}, %Wotex.Form{}, ^context}
    assert_receive {:client_request, %Request{} = request, :resolved_credential}
    assert Request.uri(request) == "https://thing.example/properties/temperature"
  end

  test "the subscription process decodes client frames and delivers Runtime values" do
    {:ok, first} = Event.new("22", event: "temperature", id: "event-22")

    pid = observation(%{frames: [first]}, :decoding_observation)

    assert_receive {:client_subscribe, %Request{} = request, :resolved_credential, ^pid}
    assert Request.uri(request) == "https://thing.example/properties/temperature"

    assert_receive {:wotex_runtime, :decoding_observation, {:ok, 22, meta}}

    assert meta == %{
             event: "temperature",
             id: "event-22",
             retry: nil,
             request_id: "stream-request",
             operation: :observeproperty
           }

    {:ok, keep_alive} = Event.new("")
    send(pid, {:wotex_transport_frame, keep_alive})
    refute_receive {:wotex_runtime, :decoding_observation, _event}, 50

    assert :ok = Subscription.stop(pid)
    assert_receive {:client_close, :integration_handle}
    refute Process.alive?(pid)
  end

  test "oversized and malformed frames become undecodable Runtime frame errors" do
    {:ok, oversized} = Event.new("123456789")
    {:ok, malformed} = Event.new("bad")

    pid = observation(%{frames: [oversized, malformed]}, :rejecting_observation)

    assert_receive {:wotex_runtime, :rejecting_observation,
                    {:error,
                     %Error{
                       code: :undecodable_frame,
                       class: :protocol,
                       details: %{cause: %{code: :sse_event_too_large, phase: :subscription}}
                     }}}

    assert_receive {:wotex_runtime, :rejecting_observation,
                    {:error,
                     %Error{
                       code: :undecodable_frame,
                       details: %{cause: %{code: :json_decode_failed, phase: :codec}}
                     }}}

    assert Process.alive?(pid)
    assert :ok = Subscription.stop(pid)
  end

  test "a lost client session stops the subscription after closing the connection" do
    pid = observation(%{}, :interrupted_observation)
    monitor = Process.monitor(pid)

    assert_receive {:client_subscribe, %Request{}, :resolved_credential, ^pid}

    send(pid, {:wotex_transport_status, :reconnected})
    assert_receive {:wotex_runtime, :interrupted_observation, {:status, :reconnected}}
    assert Process.alive?(pid)

    send(pid, {:wotex_transport_status, :session_lost})
    assert_receive {:wotex_runtime, :interrupted_observation, {:status, :session_lost}}
    assert_receive {:client_close, :integration_handle}
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :session_lost}}
  end

  test "a client monitoring the owner observes the subscription exit on explicit stop" do
    pid = observation(%{monitor_owner: true}, :monitored_observation)

    assert_receive {:client_subscribe, %Request{}, :resolved_credential, ^pid}
    assert :ok = Subscription.stop(pid)

    assert_receive {:client_close, :integration_handle}
    assert_receive {:owner_down, :normal}
  end

  test "WBH-L07-P concurrent Runtime stops issue one client close" do
    parent = self()

    close_return = fn ->
      send(parent, {:close_entered, self()})

      receive do
        :release_close -> :ok
      end
    end

    pid = observation(%{close_return: close_return}, :concurrent_stop)
    assert_receive {:client_subscribe, %Request{}, :resolved_credential, ^pid}

    tasks = for _ <- 1..2, do: Task.async(fn -> Subscription.stop(pid) end)
    assert_receive {:close_entered, ^pid}
    send(pid, :release_close)
    results = Enum.map(tasks, &Task.await/1)

    assert Enum.count(results, &(&1 == :ok)) == 1

    assert Enum.count(results, fn
             {:error, %Error{code: :subscription_not_running}} -> true
             _ -> false
           end) == 1

    assert_receive {:client_close, :integration_handle}
    refute_receive {:client_close, :integration_handle}
  end

  test "WBH-L09-P receiver death closes the stream and its Runtime owner" do
    receiver = spawn(fn -> receive do: (:stop -> :ok) end)
    pid = observation(%{monitor_owner: true}, :receiver_failure, receiver: receiver)
    monitor = Process.monitor(pid)

    assert_receive {:client_subscribe, %Request{}, :resolved_credential, ^pid}
    Process.exit(receiver, :kill)

    assert_receive {:client_close, :integration_handle}
    assert_receive {:owner_down, {:shutdown, :receiver_down}}
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :receiver_down}}
  end

  test "WBH-L10-P and WBH-S13-P linked client loss redacts its nested exit reason" do
    pid = observation(%{link_owner: true}, :linked_client_failure)
    monitor = Process.monitor(pid)
    secret = "nested-connection-process-secret"

    assert_receive {:client_subscribe, %Request{}, :resolved_credential, ^pid}
    assert_receive {:client_connection, connection}
    send(connection, {:fail, {:connection_lost, %{credential: secret}}})

    assert_receive {:wotex_runtime, :linked_client_failure, {:status, :transport_down}} = delivery
    refute inspect(delivery) =~ secret
    refute :erlang.term_to_binary(delivery) =~ secret
    assert_receive {:client_close, :integration_handle}
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :transport_down}}
  end

  test "WBH-S12-P sustained frames respect the Runtime receiver-mailbox drop boundary" do
    slow_receiver = spawn(fn -> Process.sleep(:infinity) end)
    Enum.each(1..3, &send(slow_receiver, {:backlog, &1}))

    pid =
      observation(%{}, :bounded_delivery,
        receiver: slow_receiver,
        max_queue_length: 3,
        overflow: :drop
      )

    assert_receive {:client_subscribe, %Request{}, :resolved_credential, ^pid}
    assert %{active?: true} = :sys.get_state(pid)
    {:ok, event} = Event.new("1")

    Enum.each(1..256, fn _ -> send(pid, {:wotex_transport_frame, event}) end)

    assert :ok = Subscription.stop(pid)
    assert_receive {:client_close, :integration_handle}
    assert {:message_queue_len, 3} = Process.info(slow_receiver, :message_queue_len)
    Process.exit(slow_receiver, :kill)
  end

  defp observation(client_overrides, id, opts \\ []) do
    handshake = response(200, "", [{"Content-Type", "text/event-stream"}])

    consumed =
      consumed_thing(
        Map.merge(
          %{subscribe_return: {:ok, :integration_handle, handshake}},
          client_overrides
        )
      )

    context = Context.new!(request_id: "stream-request")

    child_opts =
      [
        id: id,
        receiver: Keyword.get(opts, :receiver, self()),
        restart: :temporary
      ]
      |> maybe_put(opts, :max_queue_length)
      |> maybe_put(opts, :overflow)

    {:ok, child_spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context, child_opts)

    start_supervised!(child_spec)
  end

  defp maybe_put(target, source, key) do
    if Keyword.has_key?(source, key), do: Keyword.put(target, key, source[key]), else: target
  end

  defp consumed_thing(client_overrides) do
    {:ok, profile} = HTTP.profile()

    client_config =
      Map.merge(
        %{
          owner: self(),
          request_return: {:error, :not_configured},
          subscribe_return: {:error, :not_configured},
          close_return: :ok
        },
        client_overrides
      )

    {:ok, config} = HTTP.config(client: {FakeClient, client_config}, max_event_bytes: 8)

    credentials =
      {FakeCredentials, %{owner: self(), credential: :resolved_credential}}

    {:ok, consumed} =
      ConsumedThing.new(thing_description(),
        profiles: [profile],
        transports: %{http: HTTP.transport(config)},
        credentials: credentials
      )

    consumed
  end

  defp response(status, body, headers) do
    {:ok, response} = HTTP.Response.new(status, headers, body)
    response
  end

  defp thing_description do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:thing:1",
        "title" => "Example Thing",
        "base" => "https://thing.example/",
        "securityDefinitions" => %{"nosec" => %{"scheme" => "nosec"}},
        "security" => ["nosec"],
        "properties" => %{
          "temperature" => %{
            "type" => "number",
            "observable" => true,
            "forms" => [
              %{
                "href" => "properties/temperature",
                "contentType" => "application/json",
                "op" => "readproperty"
              },
              %{
                "href" => "properties/temperature",
                "contentType" => "application/json",
                "subprotocol" => "sse",
                "op" => "observeproperty"
              },
              %{
                "href" => "properties/temperature",
                "contentType" => "application/json",
                "subprotocol" => "sse",
                "op" => "unobserveproperty"
              }
            ]
          }
        }
      })

    td
  end
end
