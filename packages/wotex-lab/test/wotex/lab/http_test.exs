defmodule Wotex.Lab.HttpTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.HTTP
  alias Wotex.Binding.HTTP.Request, as: HTTPRequest
  alias Wotex.Binding.HTTP.Response, as: HTTPResponse
  alias Wotex.Binding.HTTP.SSE.Event
  alias Wotex.Binding.HTTP.Subscription, as: HTTPSubscription
  alias Wotex.Lab
  alias Wotex.Lab.Adapters.HTTP.ReqClient
  alias Wotex.Lab.Adapters.HTTP.SSE.Parser
  alias Wotex.Lab.Adapters.Runtime.StaticRef
  alias Wotex.Lab.Test.HttpServer
  alias Wotex.Runtime.{ConsumedThing, Context, Error, Result, Subscription}
  alias Wotex.ThingDescription

  @token "room-token-7f3a"

  setup do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:wotex, :runtime, :subscription, :open],
        &__MODULE__.subscription_opened/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  @doc false
  def subscription_opened(_event, _measurements, %{request_id: "http-stop"}, receiver),
    do: send(receiver, {:runtime_subscription_opened, self()})

  def subscription_opened(_event, _measurements, _metadata, _receiver), do: :ok

  setup do
    {:ok, server} = HttpServer.start(self())
    lab = start_supervised!({Lab, id: "http", max_children: 8})
    td = thing_description(server.port)
    {:ok, profile} = HTTP.profile()

    {:ok, config} =
      HTTP.config(
        client: {ReqClient, %{receive_timeout: 2_000}},
        max_response_bytes: 1_024,
        max_event_bytes: 64
      )

    credentials =
      {StaticRef,
       %{
         references: %{"bearer_sc" => "vault://room/http"},
         lookup: fn "vault://room/http" -> {:ok, {:bearer, @token}} end
       }}

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{profile.id => HTTP.transport(config)},
        credentials: credentials
      )

    %{server: server, lab: lab, td: td, profile: profile, config: config, consumed: consumed}
  end

  test "fixture shutdown owns the listener, live SSE connection and controller together", %{
    server: server
  } do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, server.port, [:binary, active: false], 1_000)

    :ok =
      :gen_tcp.send(
        socket,
        "GET /properties/temperature/observe HTTP/1.1\r\nhost: localhost\r\n\r\n"
      )

    assert_receive {:stream_opened, []}, 1_000
    assert {:ok, headers} = :gen_tcp.recv(socket, 0, 1_000)
    assert headers =~ "200 OK"
    stream = HttpServer.stream_pid(server.controller)
    pids = [stream, server.server, server.controller, server.owner]
    monitors = Enum.map(pids, &{&1, Process.monitor(&1)})

    log = ExUnit.CaptureLog.capture_log(fn -> assert :ok = HttpServer.stop(server) end)

    for {pid, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
      refute Process.alive?(pid)
    end

    refute log =~ "no process"
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1_000)

    assert {:error, :econnrefused} =
             :gen_tcp.connect({127, 0, 0, 1}, server.port, [:binary, active: false], 1_000)
  end

  test "finite requests cross real sockets with identity, status mapping and bounds", %{
    consumed: consumed,
    server: server
  } do
    context =
      Context.new!(request_id: "http-read", deadline: System.monotonic_time(:millisecond) + 2_000)

    assert {:ok, %Result{status: :ok, payload: 21.5, operation: :readproperty} = result} =
             ConsumedThing.read_property(consumed, "temperature", context)

    assert result.metadata.http.status == 200

    assert {:ok, %Result{status: :ok, payload: nil}} =
             ConsumedThing.write_property(consumed, "target", 23.5, context)

    assert HttpServer.target(server.controller) == "23.5"

    assert {:ok, %Result{status: :accepted, payload: %{"status" => "pending", "input" => 24}}} =
             ConsumedThing.invoke_action(consumed, "setTarget", 24, context)
  end

  test "oversized, slow, redirected, mistyped and unauthorized exchanges fail with classes", %{
    consumed: consumed,
    td: td,
    profile: profile,
    config: config
  } do
    context = Context.new!(request_id: "http-negative")

    assert {:error, %Error{code: :transport_request_failed, class: :unavailable} = error} =
             ConsumedThing.read_property(consumed, "large", context)

    assert error.details.cause.code == :client_request_failed

    quick =
      Context.new!(request_id: "http-slow", deadline: System.monotonic_time(:millisecond) + 100)

    assert {:error, %Error{class: :timeout}} = ConsumedThing.read_property(consumed, "slow", quick)

    assert {:error, %Error{class: :permanent} = redirect} =
             ConsumedThing.read_property(consumed, "redirect", context)

    assert redirect.details.cause.code == :http_status

    assert {:error, %Error{class: :protocol} = mistyped} =
             ConsumedThing.read_property(consumed, "html", context)

    assert mistyped.details.cause.code == :unexpected_response_media_type

    wrong =
      {StaticRef,
       %{
         references: %{"bearer_sc" => "ref"},
         lookup: fn _reference -> {:ok, {:bearer, "wrong"}} end
       }}

    {:ok, unauthorized} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{profile.id => HTTP.transport(config)},
        credentials: wrong
      )

    assert {:error, %Error{class: :permanent} = denied} =
             ConsumedThing.write_property(unauthorized, "target", 1.0, context)

    assert denied.details.cause.code == :http_status
    refute inspect(denied) =~ "wrong"
    refute inspect(denied) =~ @token
  end

  test "SSE streams are parsed incrementally and delivered through the runtime envelope", %{
    consumed: consumed,
    lab: lab,
    server: server
  } do
    context = Context.new!(request_id: "http-observe")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :sse_temperature,
        receiver: self(),
        restart: :temporary
      )

    {:ok, pid} = Lab.start_child(lab, :sessions, spec)
    assert_receive {:stream_opened, []}, 2_000
    refute inspect(:sys.get_state(pid)) =~ @token

    HttpServer.push(
      server.controller,
      "event: temperature\r\nid: 41\r\nretry: 250\r\ndata: 22.5\r\n\r\n"
    )

    assert_receive {:wotex_runtime, :sse_temperature,
                    {:ok, 22.5, %{event: "temperature", id: "41", retry: 250}}},
                   2_000

    HttpServer.push(server.controller, ": keep-alive\n\n")
    HttpServer.push(server.controller, "data: \"h\xC3")
    refute_receive {:wotex_runtime, :sse_temperature, _}, 50
    HttpServer.push(server.controller, "\xA9\"\n\n")
    assert_receive {:wotex_runtime, :sse_temperature, {:ok, "hé", %{id: "41"}}}, 2_000

    HttpServer.push(server.controller, "data: 1\ndata: 2\n\n")

    assert_receive {:wotex_runtime, :sse_temperature,
                    {:error, %Error{code: :undecodable_frame, class: :protocol}}},
                   2_000

    monitor = Process.monitor(pid)
    HttpServer.close_stream(server.controller)
    assert_receive {:wotex_runtime, :sse_temperature, {:status, :transport_down}}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :transport_down}}, 2_000
  end

  test "explicit stop closes the connection and oversized events end the session", %{
    consumed: consumed,
    lab: lab,
    server: server
  } do
    context = Context.new!(request_id: "http-stop")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :sse_stop,
        receiver: self(),
        restart: :temporary
      )

    {:ok, pid} = Lab.start_child(lab, :sessions, spec)
    assert_receive {:stream_opened, _headers}, 2_000
    stream = HttpServer.stream_pid(server.controller)
    stream_monitor = Process.monitor(stream)

    assert_receive {:runtime_subscription_opened, ^pid}, 2_000

    {ReqClient, session, _request_id, _operation} =
      HTTPSubscription.unwrap(:sys.get_state(pid).handle)

    assert Process.alive?(session)
    assert :ok = Subscription.stop(pid)
    refute Process.alive?(pid)
    refute Process.alive?(session)
    # The server learns about the closed socket only when it writes again.
    assert :ok = nudge_until_down(stream, stream_monitor, 20)

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :sse_big,
        receiver: self(),
        restart: :temporary
      )

    {:ok, big} = Lab.start_child(lab, :sessions, spec)
    monitor = Process.monitor(big)
    assert_receive {:stream_opened, _headers}, 2_000
    HttpServer.push(server.controller, "data: " <> String.duplicate("9", 100) <> "\n\n")
    assert_receive {:DOWN, ^monitor, :process, ^big, {:shutdown, :transport_down}}, 2_000
  end

  test "a handshake with the wrong media type fails the open without a stream", %{
    td: td,
    profile: profile,
    config: config,
    lab: lab
  } do
    {:ok, wrong_td} =
      td
      |> ThingDescription.to_map()
      |> put_in(["properties", "temperature", "forms"], [
        %{"href" => "properties/temperature", "op" => "readproperty"},
        %{
          "href" => "properties/temperature/observe-wrong-type",
          "subprotocol" => "sse",
          "op" => ["observeproperty", "unobserveproperty"]
        }
      ])
      |> ThingDescription.from_map()

    {:ok, consumed} =
      ConsumedThing.new(wrong_td,
        profiles: [profile],
        transports: %{profile.id => HTTP.transport(config)},
        credentials: {StaticRef, %{references: %{}, lookup: fn _ -> :error end}}
      )

    context = Context.new!(request_id: "http-handshake")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :sse_wrong,
        receiver: self(),
        restart: :temporary
      )

    {:ok, pid} = Lab.start_child(lab, :sessions, spec)
    monitor = Process.monitor(pid)

    assert_receive {:wotex_runtime, :sse_wrong,
                    {:error, %Error{code: :transport_subscribe_failed} = error}},
                   2_000

    assert error.details.cause.code == :sse_handshake_media_type
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, %Error{}}}, 2_000
  end

  test "the SSE parser handles line endings, comments, ids, retries and bounds" do
    parser = Parser.new(max_line_bytes: 32, max_event_bytes: 16)

    assert {:ok, [], parser} = Parser.feed(parser, ": comment\r")
    assert {:ok, [], parser} = Parser.feed(parser, "\nid: a\0b\nretry: x\nevent: e\ndata: 1")
    assert {:ok, [event], parser} = Parser.feed(parser, "\n\n")

    assert Event.data(event) == "1" and Event.event(event) == "e" and Event.id(event) == nil and
             Event.retry(event) == nil

    assert {:ok, [second], parser} = Parser.feed(parser, "data:2\r\n\r\n")
    assert Event.data(second) == "2" and Event.event(second) == nil

    assert {:ok, [bare], parser} = Parser.feed(parser, "data\n\n")
    assert Event.data(bare) == ""

    assert {:error, %Wotex.Lab.Error{code: :sse_line_too_long}} =
             Parser.feed(parser, String.duplicate("x", 40))

    assert {:error, %Wotex.Lab.Error{code: :sse_event_too_large}} =
             Parser.feed(parser, "data: " <> String.duplicate("y", 20) <> "\n")

    assert {:error, %Wotex.Lab.Error{code: :sse_event_invalid}} =
             Parser.feed(parser, "data: \xFF\n\n")
  end

  defp nudge_until_down(_stream, _monitor, 0), do: :timeout

  defp nudge_until_down(stream, monitor, attempts) do
    send(stream, {:chunk, "data: 1\n\n"})

    receive do
      {:DOWN, ^monitor, :process, ^stream, _reason} -> :ok
    after
      100 -> nudge_until_down(stream, monitor, attempts - 1)
    end
  end

  defp thing_description(port) do
    base = "http://127.0.0.1:#{port}/"

    map = %{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:wotex:lab:http:room",
      "title" => "HTTP room",
      "base" => base,
      "security" => ["nosec_sc"],
      "securityDefinitions" => %{
        "nosec_sc" => %{"scheme" => "nosec"},
        "bearer_sc" => %{"scheme" => "bearer"}
      },
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
              "href" => "properties/temperature/observe",
              "contentType" => "application/json",
              "subprotocol" => "sse",
              "op" => ["observeproperty", "unobserveproperty"]
            }
          ]
        },
        "target" => %{
          "type" => "number",
          "forms" => [
            %{
              "href" => "properties/target",
              "contentType" => "application/json",
              "op" => "writeproperty",
              "security" => ["bearer_sc"]
            }
          ]
        },
        "large" => %{
          "type" => "string",
          "forms" => [%{"href" => "properties/large", "op" => "readproperty"}]
        },
        "slow" => %{
          "type" => "number",
          "forms" => [%{"href" => "properties/slow", "op" => "readproperty"}]
        },
        "redirect" => %{
          "type" => "number",
          "forms" => [%{"href" => "properties/redirect", "op" => "readproperty"}]
        },
        "html" => %{
          "type" => "number",
          "forms" => [%{"href" => "properties/html", "op" => "readproperty"}]
        }
      },
      "actions" => %{
        "setTarget" => %{
          "input" => %{"type" => "number"},
          "forms" => [
            %{
              "href" => "actions/set-target",
              "contentType" => "application/json",
              "op" => "invokeaction"
            }
          ]
        }
      }
    }

    {:ok, td} = ThingDescription.from_map(map)
    td
  end

  test "the client maps credentials, methods, deadlines and configuration explicitly", %{
    server: server
  } do
    {:ok, get} =
      request("GET", "http://127.0.0.1:#{server.port}/properties/temperature", deadline: nil)

    assert {:ok, %HTTPResponse{status: 200}} =
             ReqClient.request(get, {:basic, "u", "p"}, [])

    assert {:ok, %HTTPResponse{status: 200}} =
             ReqClient.request(get, %{"a" => {:bearer, "t"}}, %{})

    assert {:error, :unsupported_credential} = ReqClient.request(get, :nope, %{})
    assert {:error, :unsupported_credential} = ReqClient.request(get, %{"a" => :nope}, %{})

    {:ok, trace} =
      request("TRACE", "http://127.0.0.1:#{server.port}/properties/temperature", deadline: nil)

    assert {:error, :unsupported_method} = ReqClient.request(trace, nil, %{})

    expired = DateTime.add(DateTime.utc_now(), -1, :second)

    {:ok, late} =
      request("GET", "http://127.0.0.1:#{server.port}/properties/temperature", deadline: expired)

    assert {:error, :timeout} = ReqClient.request(late, nil, %{})

    soon = DateTime.add(DateTime.utc_now(), 2, :second)

    {:ok, timely} =
      request("GET", "http://127.0.0.1:#{server.port}/properties/temperature", deadline: soon)

    assert {:ok, %HTTPResponse{}} = ReqClient.request(timely, nil, %{})

    {:ok, closed} = request("GET", "http://127.0.0.1:1/properties/temperature", deadline: nil)
    assert {:error, :transport_failed} = ReqClient.request(closed, nil, %{})
    assert {:error, :invalid_handle} = ReqClient.close(:not_a_session, %{})
    assert {:error, :invalid_config} = ReqClient.request(get, nil, :bad_config)
  end

  test "stream opens report connection failures and non-stream handshakes", %{server: server} do
    {:ok, closed} =
      request("GET", "http://127.0.0.1:1/properties/temperature/observe",
        deadline: nil,
        stream?: true
      )

    assert {:error, :connect_failed} = ReqClient.subscribe(closed, nil, self(), %{})

    {:ok, missing} =
      request("GET", "http://127.0.0.1:#{server.port}/nowhere", deadline: nil, stream?: true)

    assert {:ok, session, %HTTPResponse{status: 404}} =
             ReqClient.subscribe(missing, nil, self(), %{})

    monitor = Process.monitor(session)
    assert_receive {:DOWN, ^monitor, :process, ^session, reason}, 2_000
    assert reason in [:normal, :noproc]

    {:ok, stream} =
      request("GET", "http://127.0.0.1:#{server.port}/properties/temperature/observe",
        deadline: nil,
        stream?: true
      )

    assert {:ok, session, %HTTPResponse{status: 200}} =
             ReqClient.subscribe(stream, nil, self(), %{})

    send(session, :unrelated)
    HttpServer.push(server.controller, "unknown: field
event:
data: 3

")
    assert_receive {:wotex_transport_frame, %Event{data: "3", event: nil}}, 2_000
    assert :ok = ReqClient.close(session, %{})
    refute Process.alive?(session)
  end

  defp request(method, uri, opts) do
    stream? = Keyword.get(opts, :stream?, false)
    accept = if stream?, do: "text/event-stream", else: "application/json"

    HTTPRequest.new(method, uri, [{"accept", accept}], nil,
      request_id: "unit",
      operation: if(stream?, do: :observeproperty, else: :readproperty),
      media_type: "application/json",
      stream?: stream?,
      deadline: Keyword.get(opts, :deadline),
      max_response_bytes: 1_024,
      max_event_bytes: 64
    )
  end
end
