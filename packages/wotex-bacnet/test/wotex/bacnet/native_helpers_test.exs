defmodule Wotex.BACnet.NativeHelpersTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.BACnet.{Error, Session, TestClient}
  alias Wotex.BACnet.Test.NativeHelpersClient

  test "WBA-N02 injected client cannot turn an untyped read or unacknowledged write into success" do
    {:ok, value} = Encoding.create({:boolean, false})
    assert {:ok, ^value} = BACnet.read_property(session({:ok, value}), 1, 0, 85)

    assert_receive {:native_helper_call,
                    %{type: :read_property, property: 85, priority: nil, array_index: nil}}

    assert :ok = BACnet.write_property(session({:ok, :written}), 1, 0, 85, value)

    assert_receive {:native_helper_call,
                    %{type: :write_property, value: ^value, priority: nil, array_index: nil}}

    assert {:error, %Error{code: :invalid_value}} =
             BACnet.read_property(session({:ok, false}), 1, 0, 85)

    assert_receive {:native_helper_call, _}

    assert {:error, %Error{code: :invalid_transport_return, effect: :unknown}} =
             BACnet.write_property(session({:ok, :unacknowledged}), 1, 0, 85, value)

    assert_receive {:native_helper_call, _}

    assert {:error, %Error{code: :invalid_address}} =
             BACnet.read_property(session({:ok, value}), 1, 0, -1)

    assert {:error, %Error{code: :invalid_session}} = BACnet.write_property(nil, 1, 0, 85, value)
    assert {:error, %Error{code: :invalid_session}} = BACnet.read_properties(nil, 1, 0, [85])
    refute_receive {:native_helper_call, _}, 10
  end

  test "WBA-N03 injected batch result must contain exactly every requested typed Property" do
    {:ok, value} = Encoding.create({:null, nil})

    assert {:ok, %{85 => ^value}} =
             BACnet.read_properties(session({:ok, %{85 => value}}), 1, 0, [85])

    assert_receive {:native_helper_call, [%{property: 85}]}

    for result <- [
          {:ok, %{}},
          {:ok, %{85 => value, 77 => value}},
          {:ok, %{85 => nil}},
          {:ok, []},
          :unexpected
        ] do
      assert {:error, %Error{code: :invalid_transport_return}} =
               BACnet.read_properties(session(result), 1, 0, [85])

      assert_receive {:native_helper_call, [%{property: 85}]}
    end

    error = Error.new(:remote_error, nil, %{class: 2, code: 32})
    assert {:error, ^error} = BACnet.read_properties(session({:error, error}), 1, 0, [85])
    assert_receive {:native_helper_call, _}

    assert {:error, %Error{effect: :none}} =
             BACnet.read_properties(session({:error, %{error | effect: :unknown}}), 1, 0, [85])

    assert_receive {:native_helper_call, _}
    legacy = %Session{client: TestClient, handle: nil, timeout: 100}
    assert {:error, %Error{code: :not_supported}} = BACnet.read_properties(legacy, 1, 0, [85])
  end

  test "WBA-C03 WBA-N02 WBA-N03 late injected replies cannot outlive the helper deadline" do
    {:ok, value} = Encoding.create({:null, nil})

    for {operation, result, effect} <- [
          {:read, {:ok, value}, :none},
          {:write, {:ok, :written}, :unknown},
          {:batch, {:ok, %{85 => value}}, :none}
        ] do
      {:ok, session} =
        BACnet.connect(
          client: NativeHelpersClient,
          owner: self(),
          result: result,
          delay_ms: 75,
          timeout: 50
        )

      outcome =
        case operation do
          :read -> BACnet.read_property(session, 1, 0, 85)
          :write -> BACnet.write_property(session, 1, 0, 85, value)
          :batch -> BACnet.read_properties(session, 1, 0, [85])
        end

      assert {:error, %Error{code: :deadline_exceeded, effect: ^effect} = error} = outcome

      if operation == :batch do
        assert error.details == %{batch_index: 0, property: 85, completed_count: 0}
      end

      assert_receive {:native_helper_call, _}
      refute_receive {:native_helper_call, _}, 5
    end
  end

  test "WBA-C03 expired helper admission cannot call even an injected write port" do
    {:ok, value} = Encoding.create({:null, nil})
    {:ok, address} = Wotex.BACnet.Address.new(%{object_type: 1, instance: 0, property: 85})

    request =
      address
      |> Map.from_struct()
      |> Map.merge(%{type: :write_property, value: value})

    deadline = System.monotonic_time(:millisecond) - 1

    assert {:error, %Error{code: :deadline_exceeded, effect: :none}} =
             BACnet.send_deadline(session({:ok, :written}), request, deadline)

    assert {:not_started, %Error{code: :deadline_exceeded, effect: :none}} =
             Wotex.BACnet.NativeCall.invoke(
               session({:ok, %{85 => value}}),
               :read_properties,
               [],
               deadline
             )

    refute_receive {:native_helper_call, _}, 10
  end

  test "WBA-N04 injected discovery results must be sorted unique typed observations and finish in time" do
    alias Wotex.BACnet.Device

    {:ok, device} =
      Device.new(%{
        source: {{192, 0, 2, 20}, 47_808},
        instance: 10,
        max_apdu: 1476,
        segmentation: :no_segmentation,
        vendor_id: 260
      })

    assert {:ok, [^device]} = BACnet.who_is(session({:ok, [device]}))
    assert_receive {:native_helper_call, {:who_is, nil, nil}}
    second = %{device | instance: 11}

    for devices <- [
          [device, device],
          [second, device],
          [Map.from_struct(device)],
          [device | :improper],
          [nil],
          nil,
          List.duplicate(device, 1025),
          [%{device | max_apdu: 0}]
        ] do
      assert {:error, %Error{code: :invalid_transport_return}} =
               BACnet.who_is(session({:ok, devices}))

      assert_receive {:native_helper_call, {:who_is, nil, nil}}
    end

    {:ok, slow} =
      BACnet.connect(
        client: NativeHelpersClient,
        owner: self(),
        result: {:ok, [device]},
        delay_ms: 75,
        timeout: 50
      )

    assert {:error, %Error{code: :deadline_exceeded}} = BACnet.who_is(slow)
    assert_receive {:native_helper_call, {:who_is, nil, nil}}
    assert {:error, %Error{code: :deadline_exceeded}} = BACnet.who_is(%{slow | timeout: 9})
    refute_receive {:native_helper_call, _}, 10
    legacy = %Session{client: TestClient, handle: nil, timeout: 100}
    assert {:error, %Error{code: :not_supported}} = BACnet.who_is(legacy)
  end

  defp session(result) do
    {:ok, session} =
      BACnet.connect(client: NativeHelpersClient, owner: self(), result: result, timeout: 100)

    session
  end
end
