Code.require_file("../../support/runtime_capture.ex", __DIR__)

defmodule Wotex.CoAP.ProfileTest do
  @moduledoc false

  use ExUnit.Case, async: false
  doctest Wotex.CoAP
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Error, Message, Transport}
  alias Wotex.CoAP.Test.{RuntimeCapture, RuntimeCredentials}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, ExecutionContext, Request}
  @corpus Path.expand("../../../docs/specs/fixtures/wotex-integration-v1.json", __DIR__)
  @case Enum.find(Jason.decode!(File.read!(@corpus))["cases"], &(&1["id"] == "WCO-I-F01"))

  test "WCO-I02 profiles admit exactly UDP unary and Observe cells without acquisition" do
    unary = CoAP.profile()
    assert CoAP.profile(:udp) == {:ok, unary}
    assert BindingProfile.id(unary) == :coap
    {:ok, observed} = CoAP.profile(:udp_observe)
    assert BindingProfile.id(observed) == :coap_observe

    for profile <- [unary, observed] do
      assert BindingProfile.supports_scheme?(profile, "coap")
      refute BindingProfile.supports_scheme?(profile, "coaps")

      for media <- ["application/json", "application/octet-stream", "text/plain;charset=utf-8"],
          do: assert(BindingProfile.supports_media_type?(profile, media))

      refute BindingProfile.supports_media_type?(profile, "application/cbor")

      for operation <- [:readproperty, :writeproperty, :invokeaction],
          do: assert(BindingProfile.supports_operation?(profile, operation))

      refute BindingProfile.supports_operation?(profile, :readallproperties)
    end

    for operation <- [:observeproperty, :unobserveproperty, :subscribeevent, :unsubscribeevent] do
      refute BindingProfile.supports_operation?(unary, operation)
      assert BindingProfile.supports_operation?(observed, operation)
    end

    for mode <- [:dtls, :oscore, nil, %{}, [:udp]] do
      assert {:error, %Error{code: :unsupported_profile, class: :permanent}} = CoAP.profile(mode)
    end
  end

  test "WCO-I-F01 WCO-I02 WCO-I03 WCO-I06 real UDP Runtime projection matches the corpus" do
    input = @case["input"]
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    on_exit(fn -> :gen_udp.close(peer) end)
    affordance = input["affordance"]
    [form] = get_in(input, ["thing_description", "properties", affordance, "forms"])
    uri = URI.parse(form["href"])
    actual_href = URI.to_string(%{uri | port: port})

    td_map =
      put_in(input["thing_description"], ["properties", affordance, "forms"], [
        Map.put(form, "href", actual_href)
      ])

    {:ok, td} = Wotex.ThingDescription.from_map(td_map)
    assert input["profile_mode"] == "udp"
    {:ok, profile} = CoAP.profile(:udp)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{
          coap: {RuntimeCapture, {self(), [timeout: input["transport_options"]["timeout"]]}}
        },
        credentials: {RuntimeCredentials, []}
      )

    deadline = System.monotonic_time(:millisecond) + input["clock"]["deadline"]
    {:ok, context} = Context.new(request_id: input["request_id"], deadline: deadline)
    before_ports = MapSet.new(Port.list())
    responder = Task.async(fn -> respond(peer, input["peer_reply"]) end)
    assert {:ok, result} = ConsumedThing.read_property(consumed, affordance, context)
    request = Task.await(responder)
    assert_receive {:selected_request, selected}
    assert selected.resolved_href == actual_href
    assert {:error, :timeout} = :gen_udp.recv(peer, 0, 10)
    owned_after = MapSet.size(MapSet.difference(MapSet.new(Port.list()), before_ports))
    methods = %{1 => "get", 2 => "post", 3 => "put", 4 => "delete"}
    [accept] = Codec.option(request, 17)

    actual = %{
      "profile_id" => Atom.to_string(BindingProfile.id(profile)),
      "resolved_href" => URI.to_string(%{URI.parse(selected.resolved_href) | port: uri.port}),
      "command" => %{
        "method" => Map.fetch!(methods, request.code),
        "path" => "/" <> Enum.join(Codec.option(request, 11), "/"),
        "accept" => :binary.decode_unsigned(accept)
      },
      "result" => %{
        "request_id" => result.request_id,
        "operation" => Atom.to_string(result.operation),
        "status" => Atom.to_string(result.status),
        "payload" => result.payload,
        "metadata" => %{"code" => result.metadata.code}
      },
      "extension" => Wotex.Form.to_map(selected.form)["example:extension"],
      "request_count" => 1,
      "owned_resources_after" => owned_after
    }

    assert actual == @case["expectation"]["value"]
  end

  test "WCO-I02 WCO-I03 invalid or forged Runtime context and profile transmit nothing" do
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    on_exit(fn -> :gen_udp.close(peer) end)
    {:ok, form} = Wotex.Form.new(%{"href" => "coap://127.0.0.1:#{port}/x"})
    {:ok, context} = Context.new(request_id: "valid")
    execution = ExecutionContext.new(context, nil)

    request = %Request{
      operation: :readproperty,
      affordance_type: :property,
      affordance_name: "x",
      form: form,
      resolved_href: Wotex.Form.href(form),
      profile: CoAP.profile(),
      request_id: context.request_id,
      deadline: context.deadline,
      input: nil
    }

    before_ports = MapSet.new(Port.list())

    for bad <- [
          %{request | profile: nil},
          %{request | profile: %{request.profile | id: :forged}},
          %{request | request_id: "different"},
          %{request | affordance_type: :event},
          Map.put(request, :extra, true)
        ] do
      assert {:error, %Error{code: :invalid_transport_context}} =
               Transport.request(bad, execution, [])
    end

    assert {:error, %Error{code: :invalid_transport_context}} =
             Transport.request(request, %{execution | context: %{context | metadata: :invalid}}, [])

    assert MapSet.difference(MapSet.new(Port.list()), before_ports) == MapSet.new()
    assert {:error, :timeout} = :gen_udp.recv(peer, 0, 10)
  end

  test "WCO-I04 a response waiting on a suspended callback cannot complete beyond its budget" do
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    on_exit(fn -> :gen_udp.close(peer) end)
    form = %{"href" => "coap://127.0.0.1:#{port}/value", "contentType" => "application/json"}

    td_map =
      put_in(@case["input"]["thing_description"], ["properties", "reading"], %{"forms" => [form]})

    {:ok, td} = Wotex.ThingDescription.from_map(td_map)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [CoAP.profile()],
        transports: %{coap: {RuntimeCapture, {self(), [timeout: 500]}}},
        credentials: {RuntimeCredentials, []}
      )

    {:ok, context} = Context.new(request_id: "delayed")
    before_ports = MapSet.new(Port.list())

    for operation <- [:readproperty, :writeproperty] do
      call =
        Task.async(fn ->
          case operation do
            :readproperty -> ConsumedThing.read_property(consumed, "reading", context)
            :writeproperty -> ConsumedThing.write_property(consumed, "reading", 42, context)
          end
        end)

      assert_receive {:callback_owner, callback}, 1000
      {:ok, {host, remote_port, bytes}} = :gen_udp.recv(peer, 0, 1000)
      {:ok, message} = Codec.decode(bytes)
      assert :erlang.suspend_process(callback)
      response = %{message | type: :ack, code: 69, options: [{12, <<50>>}], payload: "42"}
      {:ok, encoded} = Codec.encode(response)
      assert :ok = :gen_udp.send(peer, host, remote_port, encoded)
      await_reply(callback, System.monotonic_time(:millisecond) + 250)
      Process.sleep(550)
      assert :erlang.resume_process(callback)
      assert {:error, error} = Task.await(call)
      assert error.details.cause.code == :deadline_exceeded
      assert error.class == if(operation == :readproperty, do: :timeout, else: :permanent)
    end

    assert MapSet.difference(MapSet.new(Port.list()), before_ports) == MapSet.new()
  end

  test "WCO-I02 WCO-I03 real unary profiles preserve all admitted media and acknowledgment cells" do
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    on_exit(fn -> :gen_udp.close(peer) end)

    for {operation, media, input, body, code, reply, format, expected} <- [
          {:readproperty, "application/json", nil, "", 69, "false", 50, false},
          {:readproperty, "application/json", nil, "", 69, "null", 50, nil},
          {:readproperty, "application/json", nil, "", 69, "0", 50, 0},
          {:readproperty, "application/json", nil, "", 69, "[]", 50, []},
          {:readproperty, "text/plain;charset=utf-8", nil, "", 69, "", 0, ""},
          {:readproperty, "application/octet-stream", nil, "", 69, <<0, 255>>, 42, <<0, 255>>},
          {:writeproperty, "application/json", nil, "null", 68, "", nil, nil},
          {:writeproperty, "application/octet-stream", <<0, 255>>, <<0, 255>>, 68, "", nil, nil},
          {:writeproperty, "text/plain;charset=utf-8", "å", "å", 68, "", nil, nil},
          {:invokeaction, "application/json", false, "false", 68, "", nil, nil},
          {:invokeaction, "application/octet-stream", <<0>>, <<0>>, 68, "", nil, nil},
          {:invokeaction, "text/plain;charset=utf-8", "", "", 68, "", nil, nil}
        ] do
      forms = [
        %{"href" => "https://unused.invalid/value", "op" => Atom.to_string(operation)},
        %{"href" => "./value", "op" => Atom.to_string(operation), "contentType" => media}
      ]

      category = if operation == :invokeaction, do: "actions", else: "properties"
      td_map = @case["input"]["thing_description"] |> Map.delete("properties")

      td_map =
        Map.merge(td_map, %{
          "base" => "coap://127.0.0.1:#{port}/",
          category => %{"value" => %{"forms" => forms}}
        })

      {:ok, td} = Wotex.ThingDescription.from_map(td_map)

      {:ok, consumed} =
        ConsumedThing.new(td,
          profiles: [CoAP.profile()],
          transports: %{coap: {Transport, [timeout: 1000]}},
          credentials: {RuntimeCredentials, []}
        )

      {:ok, context} = Context.new(request_id: "cell")

      response =
        Task.async(fn ->
          {:ok, {host, source, bytes}} = :gen_udp.recv(peer, 0, 1000)
          {:ok, request} = Codec.decode(bytes)
          options = if is_nil(format), do: [], else: [{12, Codec.uint(format)}]

          {:ok, bytes} =
            Codec.encode(%{request | type: :ack, code: code, payload: reply, options: options})

          :ok = :gen_udp.send(peer, host, source, bytes)
          request
        end)

      result =
        case operation do
          :readproperty -> ConsumedThing.read_property(consumed, "value", context)
          :writeproperty -> ConsumedThing.write_property(consumed, "value", input, context)
          :invokeaction -> ConsumedThing.invoke_action(consumed, "value", input, context)
        end

      assert {:ok, result} = result
      assert result.request_id == "cell" and result.operation == operation and result.status == :ok
      assert result.payload === expected
      assert result.metadata == %{code: code}
      request = Task.await(response)
      assert request.code == %{readproperty: 1, writeproperty: 3, invokeaction: 2}[operation]
      assert request.payload == body
      assert Codec.option(request, 11) == ["value"]
    end
  end

  defp await_reply(callback, deadline) do
    {:messages, messages} = Process.info(callback, :messages)

    if Enum.any?(messages, fn
         {_, {:ok, %Message{payload: "42"}}} -> true
         _ -> false
       end) do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(1)
      await_reply(callback, deadline)
    end
  end

  defp respond(
         peer,
         %{
           "kind" => "coap_response",
           "type" => "ack",
           "echo_request_token" => true,
           "echo_request_message_id" => true
         } = reply
       ) do
    {:ok, {host, port, bytes}} = :gen_udp.recv(peer, 0, 1000)
    {:ok, request} = Codec.decode(bytes)

    response = %Message{
      type: :ack,
      code: reply["code"],
      message_id: request.message_id,
      token: request.token,
      options: [{12, Codec.uint(reply["content_format"])}],
      payload: Base.decode16!(reply["payload_hex"], case: :mixed)
    }

    {:ok, encoded} = Codec.encode(response)
    :ok = :gen_udp.send(peer, host, port, encoded)
    request
  end
end
