defmodule Wotex.Matter.InteractionBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter

  alias Wotex.Matter.{
    Descriptor,
    Error,
    Mapping,
    RuntimeClient,
    RuntimeRelay,
    Session,
    TestClient,
    Transport
  }

  alias Wotex.Runtime.{BindingProfile, Context, ExecutionContext, Request}

  defmodule UntypedSubscriptionClient do
    @moduledoc false

    @spec subscribe(term(), term(), term(), term()) :: {:ok, :unexpected}
    def subscribe(_, _, _, _), do: {:ok, :unexpected}
  end

  defmodule PartialDescriptorClient do
    @moduledoc false

    alias Wotex.Matter.{Descriptor, Error}

    @spec request(term(), map(), pos_integer()) :: {:ok, [map()]}
    def request(owner, %{type: :read_paths, paths: paths}, _) do
      send(owner, {:descriptor_paths, Enum.map(paths, & &1.member)})
      {:ok, Enum.map(paths, &result/1)}
    end

    defp result(%{member: 3} = path),
      do: %{path: path, result: {:error, Error.new(:unsupported_attribute)}}

    defp result(path) do
      value =
        case path.member do
          0 -> [%{device_type: 0x0016, revision: 1}]
          1 -> [0x001D]
          2 -> []
        end

      {:ok, element} = Descriptor.to_element(:attribute, path, :read, value)
      %{path: path, result: {:ok, %{path: path, value: element, data_version: 4}}}
    end
  end

  @on_off %{fabric_id: 1, node_id: 1234, endpoint: 1, cluster: 6, member: 0}
  @toggle %{fabric_id: 1, node_id: 1234, endpoint: 1, cluster: 6, member: 2}
  @parts %{fabric_id: 1, node_id: 1234, endpoint: 0, cluster: 0x001D, member: 3}
  @empty %{tag: :anonymous, type: :structure, value: []}

  test "Form addresses with a non-numeric segment or no fabric authority are rejected" do
    {:ok, form} = Wotex.Form.new(%{"href" => "matter://1/1234/1/6/0"})

    for href <- ["matter://1/node/1/6/0", "matter:1234/1/6/0"] do
      assert {:error, %Error{code: :invalid_form_address}} =
               Mapping.command(form, :readproperty, nil, href)
    end
  end

  test "a PartsList element outside the u16 schema is not a valid read value" do
    element = %{tag: :anonymous, type: :array, value: [%{tag: :anonymous, type: :u8, value: 1}]}

    assert {:error, %Error{code: :invalid_value}} =
             Descriptor.validate_element(:attribute, @parts, :read, element)
  end

  test "event reads reject attribute paths before a request" do
    session = %Session{client: TestClient, handle: %{owner: self()}, timeout: 100}

    assert {:error, %Error{code: :unsupported_schema}} = Matter.read_events(session, [@on_off])
    refute_received {:matter_request, _, _}
  end

  test "an invoke response naming an unadmitted command leaves the effect unknown" do
    response = %{path: %{@toggle | member: 99}, value: @empty, status: 0}
    {:ok, session} = Matter.connect(client: TestClient, response: response)

    assert {:error, %Error{code: :unsupported_schema, effect: :unknown}} =
             Matter.invoke_command(session, @toggle, @empty)

    assert_received {:matter_request, %{type: :invoke}, _}
  end

  test "a subscription success without a subscription handle is an invalid transport return" do
    session = %Session{client: UntypedSubscriptionClient, handle: :fixture, timeout: 100}

    assert {:error, %Error{code: :invalid_transport_return}} =
             Matter.subscribe(session, %{kind: :attribute, paths: [@on_off]})
  end

  test "a root PartsList error yields a catalogue of the root endpoint only" do
    session = %Session{client: PartialDescriptorClient, handle: self(), timeout: 1_000}

    assert {:ok, catalogue} = Matter.discover_endpoints(session, %{fabric_id: 1, node_id: 1234})

    assert [%{endpoint: 0, parts: {:error, %Error{code: :unsupported_attribute}}} = root] =
             catalogue.endpoints

    assert {:ok, %{value: [0x001D], data_version: 4}} = root.server_clusters
    assert_received {:descriptor_paths, [0, 1, 2, 3]}
    refute_received {:descriptor_paths, _}
  end

  test "stream subscriptions for a dead owner or a foreign target acquire no client" do
    request = stream_request()
    {owner, monitor} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}

    assert {:error, %Error{code: :invalid_transport_context}} =
             Transport.subscribe(request, owner, execution(), stream_options())

    assert {:error, %Error{code: :invalid_transport_context}} =
             Transport.subscribe(
               request,
               self(),
               execution(),
               Keyword.put(stream_options(), :target, "2")
             )

    refute_received {:matter_connect, _}
  end

  test "a relay start without a typed address fails before client acquisition" do
    assert {:error, %Error{code: :invalid_subscription}} =
             RuntimeRelay.start(
               self(),
               "request",
               :observeproperty,
               :attribute,
               @on_off,
               [client: RuntimeClient, test_pid: self()],
               [],
               1_000
             )

    refute_received {:matter_connect, _}
  end

  test "stopping a bound relay releases its subscription and session" do
    {:ok, handle} = Transport.subscribe(stream_request(), self(), execution(), stream_options())
    relay = handle.pid
    assert_receive {:matter_subscribe, ^relay, ^relay, _, _, _}

    assert :ok = GenServer.stop(relay)
    assert_receive {:matter_unsubscribe, ^relay, _, _}
    assert_receive :disconnected
  end

  test "an attribute report outside its schema closes the route with the typed error" do
    {:ok, handle} = Transport.subscribe(stream_request(), self(), execution(), stream_options())
    relay = handle.pid
    monitor = Process.monitor(relay)
    assert_receive {:matter_subscribe, ^relay, ^relay, _, _, reference}
    metadata = %{kind: :attribute, path: @on_off, data_version: 1}

    send(relay, {:wotex_matter, reference, {:ok, %{@empty | type: :u8, value: 1}, metadata}})

    assert_receive {:wotex_transport, {:error, %Error{code: :invalid_value}}}
    assert_receive {:wotex_transport_status, :transport_down}
    assert_receive {:DOWN, ^monitor, :process, ^relay, :normal}
    assert_received {:matter_unsubscribe, ^relay, _, _}
    assert_received :disconnected
    refute_received {:wotex_transport_frame, _}
  end

  defp stream_request do
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

    href = "matter://1/1234/1/6/0"
    {:ok, form} = Wotex.Form.new(%{"href" => href, "op" => "observeproperty"})

    %Request{
      operation: :observeproperty,
      affordance_type: :property,
      affordance_name: "fixture",
      form: form,
      resolved_href: href,
      profile: profile,
      request_id: "request-#{System.unique_integer([:positive])}",
      deadline: nil,
      input: nil
    }
  end

  defp execution do
    {:ok, context} = Context.new(request_id: "stream")
    ExecutionContext.new(context, nil)
  end

  defp stream_options, do: [client: RuntimeClient, target: "1", test_pid: self(), timeout: 500]
end
