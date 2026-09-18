defmodule Wotex.BACnet.BACstackBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.APDU
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{Address, BACstack, Error, IPv4, StackClient, Tags, Transport}
  alias Wotex.Runtime.Request

  @destination {{192, 0, 2, 20}, 47_808}
  @peer %{max_apdu: 50, max_segments: 1, segmentation: :no_segmentation}
  @read %{type: :read_property, object_type: :analog_value, instance: 7, property: :present_value}

  test "a raw client lost during dispatch fails closed and leaves a write effect unknown" do
    client =
      spawn(fn ->
        receive do
          {:"$gen_call", _, {:send, _, _, _}} -> exit(:client_lost)
        end
      end)

    monitor = Process.monitor(client)
    config = raw_config(client, true)
    write = Map.merge(@read, %{type: :write_property, value: Encoding.create!({:real, 2.0})})

    assert {:error, %Error{code: :connection_closed, effect: :unknown}} =
             BACstack.exchange(config, write, deadline())

    assert_receive {:DOWN, ^monitor, :process, ^client, :client_lost}

    assert {:error, %Error{code: :connection_closed, effect: :none}} =
             BACstack.exchange(config, @read, deadline())
  end

  test "dispatch rejects an expired deadline or a disabled write before reaching the client" do
    config = raw_config(self(), false)
    write = Map.merge(@read, %{type: :write_property, value: Encoding.create!({:real, 2.0})})
    expired = System.monotonic_time(:millisecond) - 1

    assert {:error, %Error{code: :deadline_exceeded}} = BACstack.exchange(config, @read, expired)

    assert {:error, %Error{code: :write_configuration_required}} =
             BACstack.exchange(config, write, deadline())

    refute_received {:"$gen_call", _, _}
  end

  test "a bounded receive policy requires the verified wrapper" do
    assert {:error, %Error{code: :unbounded_receive_policy}} =
             BACstack.connect(
               stack_client: self(),
               destination: @destination,
               receive_policy: :wotex_bounded
             )
  end

  test "handles and budgets outside the client contract fail without work" do
    handle = %{owner: self(), generation: make_ref()}

    assert {:error, %Error{code: :invalid_subscription}} =
             BACstack.subscribe(handle, %{}, self(), 0)

    assert {:error, %Error{code: :invalid_subscription}} =
             IPv4.subscribe(%{stack: handle}, %{}, self(), 60_001)

    assert :ok = BACstack.disconnect(:not_a_handle)
    assert {:error, %Error{code: :invalid_message}} = Wotex.BACnet.send(nil, @read)
    refute_received {:"$gen_call", _, _}
  end

  test "batch admission rejects invalid, non-normalized and malformed request lists" do
    handle = %{owner: self(), generation: make_ref()}

    assert {:error, %Error{code: :invalid_address}} =
             BACstack.read_properties(
               handle,
               [%{object_type: 1, instance: 0, property: :unknown}],
               1000
             )

    for requests <- [
          [%{object_type: 1, instance: 0, property: 85}],
          [%{object_type: 1, instance: 0, property: 85}, :not_a_request]
        ] do
      assert {:error, %Error{code: :invalid_properties}} =
               BACstack.read_properties(handle, requests, 1000)
    end

    refute_received {:"$gen_call", _, _}
  end

  test "transport failures and out-of-range remote codes never become acknowledgments" do
    {:ok, address} = Address.new(@read)

    assert {:error, %Error{code: :transport_error}} =
             BACstack.response({:error, :econnrefused}, address, :read_property)

    remote = %APDU.Error{
      invoke_id: 0,
      service: :subscribe_cov,
      class: :property,
      code: 70_000,
      payload: []
    }

    assert {:error, %Error{code: :invalid_response}} =
             BACstack.control_response({:ok, remote}, :subscribe_cov)
  end

  test "a discovery send to a client that already exited is a closed connection" do
    client = spawn(fn -> :ok end)
    monitor = Process.monitor(client)
    assert_receive {:DOWN, ^monitor, :process, ^client, _}
    apdu = %APDU.UnconfirmedServiceRequest{service: :who_is, parameters: []}

    assert {:error, %Error{code: :connection_closed}} =
             StackClient.discovery_send(client, @destination, apdu, deadline(), self(), self())
  end

  test "a character string with a two-octet extended length keeps every byte" do
    bytes = :binary.copy("a", 299)

    assert {:ok, [character_string: %{character_set: 0, bytes: ^bytes}]} =
             Tags.decode(<<0x75, 254, 300::16, 0, bytes::binary>>)
  end

  test "a runtime frame with an invalid native value keeps its typed error" do
    {:ok, form} = Wotex.Form.new(%{"href" => "bacnet://123/1,7/85", "op" => "observeproperty"})
    {:ok, value} = Encoding.create({:real, 1.5})
    destination = {{127, 0, 0, 1}, 55_834}

    request = %Request{
      operation: :observeproperty,
      affordance_type: :property,
      affordance_name: "reading",
      form: form,
      resolved_href: "bacnet://123/1,7/85",
      profile: nil,
      request_id: "frame-1",
      deadline: nil,
      input: nil
    }

    metadata = %{
      source: destination,
      device_instance: 123,
      process_identifier: 1,
      object_type: 1,
      instance: 7,
      property: 85,
      array_index: nil,
      time_remaining: 60,
      report_values: [%{property: 85, array_index: nil, priority: nil, value: value}]
    }

    config = [target: "123", destination: destination]
    assert {:ok, _, _} = Transport.decode_frame({:value, value, metadata}, request, config)

    assert {:error, %Error{}} =
             Transport.decode_frame({:value, self(), metadata}, request, config)
  end

  defp raw_config(client, writes),
    do: %{
      client: client,
      stack_client_kind: :bacstack,
      destination: @destination,
      writes: writes,
      peer_receive: @peer
    }

  defp deadline, do: System.monotonic_time(:millisecond) + 1000
end
