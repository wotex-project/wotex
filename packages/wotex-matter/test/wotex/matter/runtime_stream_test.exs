defmodule Wotex.Matter.RuntimeStreamTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter
  alias Wotex.Matter.{Error, RuntimeClient, Transport}
  alias Wotex.Runtime.{BindingProfile, Context, ExecutionContext, Request}

  @attribute_path %{fabric_id: 1, node_id: 1234, endpoint: 1, cluster: 6, member: 0}
  @writable_path %{fabric_id: 1, node_id: 1234, endpoint: 1, cluster: 513, member: 17}
  @event_path %{fabric_id: 1, node_id: 1234, endpoint: 1, cluster: 57, member: 3}
  @attribute_value %{tag: :anonymous, type: :boolean, value: false}
  @write_value %{tag: :anonymous, type: :i16, value: 2_150}
  @command_value %{tag: :anonymous, type: :structure, value: []}
  @event_value %{
    tag: :anonymous,
    type: :structure,
    value: [%{tag: {:context, 0}, type: :boolean, value: true}]
  }

  test "WMA-V11 controller Property reads, writes and Actions use typed services" do
    read = request(:readproperty, :property, @attribute_path)

    read_response = %{
      path: @attribute_path,
      value: @attribute_value,
      data_version: 7
    }

    assert {:ok, result} = Transport.request(read, execution("read"), options(read_response))
    assert result.payload == @attribute_value

    assert result.metadata == %{
             matter_kind: :attribute,
             path: @attribute_path,
             status: 0,
             data_version: 7
           }

    assert_receive {:matter_request, %{type: :read}, timeout} when timeout > 0
    assert_receive :disconnected

    write = request(:writeproperty, :property, @writable_path, @write_value)
    write_response = %{path: @writable_path, status: 0}

    assert {:ok, result} = Transport.request(write, execution("write"), options(write_response))
    assert result.payload == :written

    assert result.metadata == %{
             matter_kind: :attribute,
             path: @writable_path,
             status: 0
           }

    assert_receive {:matter_request, %{type: :write, value: @write_value}, timeout}
                   when timeout > 0

    assert_receive :disconnected

    invoke = request(:invokeaction, :action, @attribute_path, @command_value)
    invoke_response = %{path: nil, value: nil, status: 0}

    assert {:ok, result} =
             Transport.request(invoke, execution("invoke"), options(invoke_response))

    assert result.payload == nil

    assert result.metadata == %{
             matter_kind: :command,
             path: @attribute_path,
             response_path: nil,
             status: 0
           }

    assert_receive {:matter_request, %{type: :invoke, value: @command_value}, timeout}
                   when timeout > 0

    assert_receive :disconnected
  end

  test "WMA-V11 attribute reports retain DataVersion and cancel through the original route" do
    request = request(:observeproperty, :property, @attribute_path)
    options = options(:unused)

    assert {:ok, handle} = Transport.subscribe(request, self(), execution("observe"), options)

    assert_receive {:matter_subscribe, relay, receiver, native_request, timeout, reference}
                   when timeout > 0

    assert receiver == relay
    assert native_request.kind == :attribute
    assert native_request.paths == [@attribute_path]
    assert native_request.resubscribe == false

    metadata = %{kind: :attribute, path: @attribute_path, data_version: 9, initial: true}
    send(relay, {:wotex_matter, reference, {:ok, @attribute_value, metadata}})

    assert_receive {:wotex_transport_frame, frame}

    assert {:ok, @attribute_value,
            %{
              matter_kind: :attribute,
              path: @attribute_path,
              status: 0,
              data_version: 9
            }} = Transport.decode_frame(frame, request, options)

    updated = %{metadata | data_version: 10, initial: false}
    send(relay, {:wotex_matter, reference, {:ok, @attribute_value, updated}})
    assert_receive {:wotex_transport_frame, update_frame}

    assert {:ok, @attribute_value, %{data_version: 10}} =
             Transport.decode_frame(update_frame, request, options)

    send(relay, {:wotex_matter, make_ref(), {:ok, @attribute_value, metadata}})
    refute_receive {:wotex_transport_frame, _}, 20

    changed = request(:unobserveproperty, :property, %{@attribute_path | node_id: 999})

    assert :ok =
             Transport.unsubscribe(
               handle,
               changed,
               execution("stop"),
               Keyword.put(options, :target, "other")
             )

    assert_receive {:matter_unsubscribe, ^relay, subscription, cleanup_timeout}
                   when cleanup_timeout > 0

    assert subscription.reference == reference
    assert_receive :disconnected
  end

  test "WMA-V11 Event streams preserve event identity and reject forged frames" do
    request = request(:subscribeevent, :event, @event_path)
    options = options(:unused)

    assert {:ok, handle} = Transport.subscribe(request, self(), execution("event"), options)
    assert_receive {:matter_subscribe, relay, receiver, _, _, reference}
    assert receiver == relay

    metadata = %{
      kind: :event,
      path: @event_path,
      event_number: 42,
      priority: 2,
      timestamp: %{kind: :epoch, value: 17}
    }

    send(relay, {:wotex_matter, reference, {:ok, @event_value, metadata}})
    assert_receive {:wotex_transport_frame, frame}

    assert :ignore =
             Transport.decode_frame({:value, @event_value, metadata}, request, options)

    wrong_request = request(:subscribeevent, :event, %{@event_path | node_id: 999})
    assert :ignore = Transport.decode_frame(frame, wrong_request, options)

    assert {:ok, @event_value,
            %{
              matter_kind: :event,
              path: @event_path,
              status: 0,
              event_number: 42,
              priority: 2,
              timestamp: %{kind: :epoch, value: 17}
            }} = Transport.decode_frame(frame, request, options)

    assert :ignore = Transport.decode_frame(frame, request, options)
    assert :ok = Transport.unsubscribe(handle, request, execution("stop-event"), options)
    assert_receive {:matter_unsubscribe, ^relay, _, _}
    assert_receive :disconnected
  end

  test "WMA-V11 terminal session loss and Runtime owner death release native resources" do
    request = request(:observeproperty, :property, @attribute_path)
    options = options(:unused)

    assert {:ok, handle} = Transport.subscribe(request, self(), execution("lost"), options)
    assert_receive {:matter_subscribe, relay, receiver, _, _, reference}
    assert receiver == relay

    send(relay, {:wotex_matter, reference, {:error, Error.new(:subscription_failed)}})
    assert_receive {:wotex_transport, {:error, %Error{code: :subscription_failed}}}
    assert_receive {:matter_unsubscribe, ^relay, _, _}
    assert_receive :disconnected
    assert_receive {:wotex_transport_status, :session_lost}
    assert :ok = Transport.unsubscribe(handle, request, execution("lost-stop"), options)

    assert {:ok, status_handle} =
             Transport.subscribe(request, self(), execution("status"), options)

    assert_receive {:matter_subscribe, status_relay, status_receiver, _, _, status_reference}
    assert status_receiver == status_relay

    send(
      status_relay,
      {:wotex_matter, status_reference, {:status, :resubscribing, %{continuity: :lost}}}
    )

    assert_receive {:wotex_transport, {:error, %Error{code: :unsupported_stream_status}}}
    assert_receive {:matter_unsubscribe, ^status_relay, _, _}
    assert_receive :disconnected
    assert_receive {:wotex_transport_status, :transport_down}
    assert :ok = Transport.unsubscribe(status_handle, request, execution("status-stop"), options)

    parent = self()
    owner = spawn(fn -> receive do: (message -> send(parent, {:owner_message, message})) end)

    assert {:ok, owner_handle} =
             Transport.subscribe(request, owner, execution("death"), options)

    assert_receive {:matter_subscribe, second_relay, second_receiver, _, _, _}
    assert second_receiver == second_relay
    Process.exit(owner, :kill)
    assert_receive {:matter_unsubscribe, ^second_relay, _, _}
    assert_receive :disconnected
    assert :ok = Transport.unsubscribe(owner_handle, request, execution("death-stop"), options)
  end

  test "unsupported credentials and stream options fail before client acquisition" do
    request = request(:readproperty, :property, @attribute_path)
    {:ok, context} = Context.new(request_id: "credential")
    credential = ExecutionContext.new(context, %{token: "secret"})

    assert {:error, %Error{code: :invalid_transport_context}} =
             Transport.request(request, credential, options(:unused))

    stream = request(:observeproperty, :property, @attribute_path)

    assert {:error, %Error{code: :invalid_transport_context}} =
             Transport.subscribe(stream, self(), credential, options(:unused))

    invalid_options = Keyword.put(options(:unused), :subscription_options, resubscribe: true)

    assert {:error, %Error{code: :invalid_subscription}} =
             Transport.subscribe(stream, self(), execution("invalid"), invalid_options)

    refute_receive {:matter_request, _, _}
    refute_receive {:matter_subscribe, _, _, _, _, _}
    refute_receive :disconnected
  end

  test "opening report overflow fails establishment and releases its native route" do
    request = request(:observeproperty, :property, @attribute_path)
    metadata = %{kind: :attribute, path: @attribute_path, data_version: 1}
    delivery = {:ok, @attribute_value, metadata}

    options =
      :unused
      |> options()
      |> Keyword.put(:opening_deliveries, List.duplicate(delivery, 65))

    assert {:error, %Error{code: :receiver_overflow}} =
             Transport.subscribe(request, self(), execution("opening-overflow"), options)

    assert_receive {:matter_subscribe, relay, receiver, _, _, reference}
    assert receiver == relay
    assert_receive {:matter_unsubscribe, ^relay, subscription, _}
    assert subscription.reference == reference
    assert_receive :disconnected
    refute_receive {:wotex_transport_frame, _}
  end

  test "explicit health probe performs the addressed read while compatibility remains fail closed" do
    response = %{path: @attribute_path, value: @attribute_value, data_version: nil}

    assert {:ok, session} =
             Matter.connect(client: RuntimeClient, test_pid: self(), response: response)

    assert {:error, %Error{code: :probe_required}} = Matter.health_check(session)
    assert {:ok, report} = Matter.health_check(session, @attribute_path)
    assert report.value == @attribute_value
    assert report.data_version == nil
    assert_receive {:matter_request, %{type: :read}, timeout} when timeout > 0
    assert :ok = Matter.disconnect(session)
    assert_receive :disconnected
  end

  defp request(operation, affordance, path, input \\ nil) do
    {:ok, profile} =
      BindingProfile.new(
        id: :matter_controller,
        schemes: ["matter"],
        operations: [
          :readproperty,
          :writeproperty,
          :invokeaction,
          :observeproperty,
          :unobserveproperty,
          :subscribeevent,
          :unsubscribeevent
        ],
        media_types: []
      )

    href = href(path)
    {:ok, form} = Wotex.Form.new(%{"href" => href, "op" => Atom.to_string(operation)})

    %Request{
      operation: operation,
      affordance_type: affordance,
      affordance_name: "fixture",
      form: form,
      resolved_href: href,
      profile: profile,
      request_id: "request-#{System.unique_integer([:positive])}",
      deadline: nil,
      input: input
    }
  end

  defp execution(id) do
    {:ok, context} = Context.new(request_id: id)
    ExecutionContext.new(context, nil)
  end

  defp options(response),
    do: [client: RuntimeClient, target: "1", test_pid: self(), response: response, timeout: 500]

  defp href(path) do
    "matter://#{path.fabric_id}/#{path.node_id}/#{path.endpoint}/#{path.cluster}/#{path.member}"
  end
end
