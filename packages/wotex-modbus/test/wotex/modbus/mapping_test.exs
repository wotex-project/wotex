defmodule Wotex.Modbus.MappingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Modbus.{Mapping, TestPeer, Transport}
  alias Wotex.Runtime.{Context, ExecutionContext, Request}

  test "typed Forms preserve extensions and honor one-based and zero-based addresses" do
    form = %{
      "href" => "modbus+tcp://127.0.0.1/1/2?quantity=2",
      "op" => "readproperty",
      "modv:entity" => "HoldingRegister",
      "modv:type" => "xsd:float",
      "vendor:calibration" => %{"x" => 1}
    }

    assert {:ok, mapping} = Mapping.command(form, :readproperty)
    assert mapping.command.address.offset == 1
    assert mapping.endpoint.port == 502
    assert Wotex.Form.to_map(mapping.form) == form
    assert {:ok, 1.5} = Mapping.decode(mapping, [0x3FC0, 0])
    assert {:ok, :written} = Mapping.decode(mapping, :written)

    assert {:ok, zero} =
             Mapping.command(Map.put(form, "modv:zeroBasedAddressing", true), :readproperty)

    assert zero.command.address.offset == 2

    assert {:ok, relative} =
             Mapping.command(Map.put(form, "href", "/1/3?quantity=2"), :readproperty, nil,
               base: "modbus+tcp://127.0.0.1:1502/"
             )

    assert relative.endpoint.port == 1502
  end

  test "all supported entities and explicit function names select correct operations" do
    for {entity, op, quantity, input, function} <- [
          {"Coil", :readproperty, 1, nil, 1},
          {"DiscreteInput", :readproperty, 1, nil, 2},
          {"HoldingRegister", :readproperty, 1, nil, 3},
          {"InputRegister", :readproperty, 1, nil, 4},
          {"Coil", :writeproperty, 1, true, 5},
          {"Coil", :invokeaction, 2, [true, false], 15},
          {"HoldingRegister", :writeproperty, 1, 7, 6},
          {"HoldingRegister", :invokeaction, 2, [7, 8], 16}
        ] do
      assert {:ok, mapping} = Mapping.command(form(%{"modv:entity" => entity}, quantity), op, input)
      assert mapping.command.function == function
      assert {:ok, [3]} = Mapping.decode(mapping, [3])
    end

    for {name, op, input} <- [
          {"readCoil", :readproperty, nil},
          {"readDiscreteInput", :readproperty, nil},
          {"readHoldingRegisters", :readproperty, nil},
          {"readInputRegisters", :readproperty, nil},
          {"writeSingleCoil", :writeproperty, true},
          {"writeSingleHoldingRegister", :writeproperty, 1},
          {"writeMultipleCoils", :writeproperty, [true]},
          {"writeMultipleHoldingRegisters", :writeproperty, [1]}
        ] do
      assert {:ok, _} = Mapping.command(form(%{"modv:function" => name}), op, input)
    end

    for {kind, input, quantity} <- [{"xsd:short", -1, 1}, {"xsd:float", 1.5, 2}] do
      map = form(%{"modv:entity" => "HoldingRegister", "modv:type" => kind}, quantity)
      assert {:ok, _} = Mapping.command(map, :writeproperty, input)
    end
  end

  test "unsupported and ambiguous Forms fail before IO" do
    for changes <- [
          %{"href" => "http://127.0.0.1/1/1"},
          %{"href" => "modbus+tcp://user:secret@127.0.0.1/1/1"},
          %{"href" => "modbus+tcp://127.0.0.1/1/1#fragment"},
          %{"href" => "modbus+tcp://127.0.0.1/1"},
          %{"href" => "modbus+tcp://127.0.0.1/x/1"},
          %{"href" => "modbus+tcp://127.0.0.1/1/1?quantity=0"},
          %{"href" => "modbus+tcp://127.0.0.1/1/1?quantity=1&quantity=2"},
          %{"modv:zeroBasedAddressing" => "yes"},
          %{"modv:type" => "xsd:unknown"},
          %{"modv:mostSignificantByte" => nil},
          %{"modv:entity" => "Unknown"},
          %{"op" => "invokeaction"}
        ] do
      assert {:error, _} =
               Mapping.command(Map.merge(form(%{"modv:entity" => "Coil"}), changes), :readproperty)
    end

    assert {:error, _} = Mapping.command(form(%{}), :readproperty)
    assert {:error, _} = Mapping.command(form(%{"modv:function" => "typo"}), :readproperty)

    assert {:error, _} =
             Mapping.command(form(%{"modv:function" => "readCoil"}), :writeproperty, true)

    assert {:error, _} =
             Mapping.command(form(%{"modv:entity" => "InputRegister"}), :writeproperty, 1)

    assert {:error, _} = Mapping.command(form(%{"modv:entity" => "Coil"}), :observeproperty)

    assert {:error, _} =
             Mapping.command(form(%{"modv:entity" => "HoldingRegister"}, 2), :writeproperty, [1])

    assert {:error, _} = Mapping.command(nil, :readproperty)
  end

  test "Runtime transport returns identity-bound results and closes every session" do
    {peer, port} = TestPeer.start(fn _, _, _ -> <<3, 2, 0, 42>> end)

    {:ok, f} =
      Wotex.Form.new(%{
        "href" => "modbus+tcp://127.0.0.1:#{port}/1/1",
        "modv:entity" => "HoldingRegister"
      })

    request = request(f)
    {:ok, context} = Context.new(request_id: "read-1")
    execution = ExecutionContext.new(context, nil)

    assert {:ok, result} =
             Transport.request(
               %{request | deadline: System.monotonic_time(:millisecond) + 1000},
               execution,
               []
             )

    assert result.request_id == "read-1"
    assert result.operation == :readproperty
    assert result.payload == [42]
    assert :ok = Task.await(peer)

    assert {:error, %{code: :deadline_exceeded}} =
             Transport.request(
               %{request | deadline: System.monotonic_time(:millisecond) - 1},
               execution,
               []
             )

    assert {:error, %{code: :deadline_exceeded}} =
             Transport.request(
               %{request | deadline: DateTime.add(DateTime.utc_now(), -1)},
               execution,
               []
             )

    assert {:error, _} = Transport.request(%{request | deadline: :invalid}, execution, [])
    assert {:error, _} = Transport.request(request, execution, timeout: 0)

    for config <- [
          [:invalid],
          [unknown: true],
          [timeout: 100, timeout: 200],
          [security: :tls],
          [security: :none, security: :tls]
        ] do
      assert {:error, %Wotex.Modbus.Error{}} = Transport.request(request, execution, config)
    end

    assert {:error, _} = Transport.request(request, ExecutionContext.new(context, "secret"), [])
    assert {:error, _} = Transport.subscribe(nil, nil, nil, nil)
    assert {:error, _} = Transport.unsubscribe(nil, nil, nil, nil)
  end

  defp form(extra, quantity \\ 1),
    do: Map.merge(%{"href" => "modbus+tcp://127.0.0.1/1/1?quantity=#{quantity}"}, extra)

  defp request(form),
    do: %Request{
      operation: :readproperty,
      affordance_type: :property,
      affordance_name: "reading",
      form: form,
      resolved_href: Wotex.Form.href(form),
      profile: nil,
      request_id: "read-1",
      deadline: nil,
      input: nil
    }
end
