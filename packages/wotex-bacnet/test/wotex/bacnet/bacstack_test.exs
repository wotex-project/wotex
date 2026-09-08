defmodule Wotex.BACnet.BACstackTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BACnet.Protocol.{APDU, ObjectIdentifier, Services}
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{Address, BACstack}

  @message %{
    type: :read_property,
    object_type: :analog_value,
    instance: 7,
    property: :present_value
  }

  property "concrete object/property ranges preserve their numeric identity" do
    check all(
            object <- integer(0..1023),
            instance <- integer(0..4_194_302),
            property <- integer(0..4_194_303),
            index <- integer(0..4_294_967_295)
          ) do
      input = %{object_type: object, instance: instance, property: property, array_index: index}
      assert {:ok, address} = Address.new(input)
      assert Map.take(Map.from_struct(address), Map.keys(input)) == input
      assert {:error, _} = Address.new(%{input | instance: instance + 4_194_303})
    end
  end

  test "only matching read acknowledgments return raw application tags" do
    {:ok, address} = Address.new(@message)
    value = Encoding.create!({:real, 1.5})

    ack = %Services.Ack.ReadPropertyAck{
      object_identifier: %ObjectIdentifier{type: :analog_value, instance: 7},
      property_identifier: :present_value,
      property_array_index: nil,
      property_value: value
    }

    {:ok, apdu} = Services.Ack.ReadPropertyAck.to_apdu(ack, 0)
    assert {:ok, ^value} = BACstack.response({:ok, apdu}, address, :read_property)

    for change <- [%{instance: 8}, %{object_type: 1}, %{property: 77}, %{array_index: 0}],
        do:
          assert(
            match?(
              {:error, %{code: :response_mismatch}},
              BACstack.response({:ok, apdu}, struct!(address, change), :read_property)
            )
          )

    assert {:error, _} =
             BACstack.response({:ok, %{apdu | service: :write_property}}, address, :read_property)

    assert {:ok, :written} =
             BACstack.response(
               {:ok, %APDU.SimpleACK{invoke_id: 0, service: :write_property}},
               address,
               :write_property
             )

    for response <- [
          nil,
          {:ok, nil},
          {:ok, :ok},
          {:error, :timeout},
          {:ok, %APDU.SimpleACK{invoke_id: 0, service: :read_property}},
          {:ok,
           %APDU.Error{
             invoke_id: 0,
             service: :read_property,
             class: :property,
             code: :unknown_property,
             payload: []
           }},
          {:ok, %APDU.Abort{invoke_id: 0, sent_by_server: true, reason: :other}},
          {:ok, %APDU.Reject{invoke_id: 0, reason: :other}}
        ],
        do: assert(match?({:error, _}, BACstack.response(response, address, :read_property)))
  end

  test "borrowed client lifetime and exact outgoing service construction" do
    parent = self()

    stack =
      spawn(fn ->
        receive do
          {:"$gen_call", from, {:send, _, apdu, _}} ->
            send(parent, {:apdu, apdu})
            GenServer.reply(from, {:ok, %APDU.SimpleACK{invoke_id: 0, service: :write_property}})

            receive do
              :stop -> :ok
            end
        end
      end)

    assert {:ok, handle} =
             BACstack.connect(
               stack_client: stack,
               destination: {{127, 0, 0, 1}, 47_808},
               writes: true
             )

    message =
      Map.merge(@message, %{
        type: :write_property,
        value: Encoding.create!({:real, 2.0}),
        priority: 8
      })

    assert {:ok, :written} = BACstack.request(handle, message, 1000)
    assert_receive {:apdu, %{service: :write_property}}
    assert :ok = BACstack.disconnect(handle)
    assert Process.alive?(stack)
    send(stack, :stop)
    assert {:error, _} = BACstack.request(%{handle | writes: false}, message, 100)
    assert {:error, _} = BACstack.request(handle, @message, 10)
    assert {:error, _} = BACstack.request(handle, %{}, 10)

    for opts <- [
          [],
          [stack_client: self(), destination: {{999, 0, 0, 1}, 1}],
          [stack_client: self(), destination: nil]
        ],
        do: assert(match?({:error, _}, BACstack.connect(opts)))
  end

  test "address ranges keep index zero and reject reserved instance and priority" do
    assert {:ok, %{array_index: 0}} = Address.new(Map.put(@message, :array_index, 0))

    for {key, value} <- [
          object_type: 1024,
          instance: 4_194_303,
          property: 4_194_304,
          array_index: -1,
          priority: 0,
          priority: 17
        ],
        do: assert(match?({:error, _}, Address.new(Map.put(@message, key, value))))

    assert {:error, _} = Address.validate_message(Map.put(@message, :type, :write_property))
  end
end
