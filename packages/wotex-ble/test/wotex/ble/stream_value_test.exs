defmodule Wotex.BLE.StreamValueTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.BLE.BlueZ.Stream
  alias Wotex.BLE.{Error, Subscription}

  @corpus Path.expand("../../../docs/specs/fixtures/contract-v1.json", __DIR__)

  test "WBL-P05 WBL-V07 mode selection preserves the BlueZ procedure limitation" do
    for {flags, requested, effective} <- [
          {["notify"], :auto, :notify},
          {["notify"], :notify, :notify},
          {["indicate"], :auto, :indicate},
          {["indicate"], :indicate, :indicate},
          {["notify", "indicate"], :auto, :bluez_selected},
          {["notify", "future-flag"], :auto, :notify}
        ] do
      assert {:ok, ^effective} = Stream.mode(flags, requested)
    end

    for {flags, requested} <- [
          {[], :auto},
          {["read"], :notify},
          {["notify"], :indicate},
          {["indicate"], :notify}
        ] do
      assert {:error, %Error{code: :not_supported}} = Stream.mode(flags, requested)
    end

    for requested <- [:notify, :indicate] do
      assert {:error, %Error{code: :unsupported_procedure_selection}} =
               Stream.mode(["notify", "indicate"], requested)
    end

    for flags <- [
          nil,
          [1],
          ["notify", "notify"],
          [<<255>>],
          [String.duplicate("x", 65)],
          [""],
          List.duplicate("notify", 65),
          ["notify" | :bad]
        ] do
      assert {:error, %Error{code: :invalid_characteristic}} = Stream.mode(flags, :auto)
    end

    assert {:error, %Error{code: :invalid_options}} = Stream.mode(["notify"], :guess)
  end

  test "WBL-F08 concrete ambiguous-procedure case binds to its exact rejection" do
    fixture =
      @corpus
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.find(&(&1["id"] == "WBL-F08"))

    assert fixture["input"]["mode"] == "indicate"
    assert {:error, %Error{} = error} = Stream.mode(fixture["input"]["flags"], :indicate)
    expected = fixture["expectation"]["value"]["result"]["error"]

    assert expected == %{
             "code" => Atom.to_string(error.code),
             "effect" => Atom.to_string(error.effect)
           }
  end

  test "WBL-C05 receiver, queue and codec policies are bounded before acquisition" do
    address = %{service: "180f", characteristic: "2a19"}

    assert {:ok,
            %{
              receiver: receiver,
              max_queue_length: 1000,
              requested_mode: :auto,
              timeout: 5000,
              type: :bytes
            }} = Stream.options(%{address: address}, 5000, self())

    assert receiver == self()

    assert {:ok, %{max_queue_length: 10_000, type: :uint16, codec: [byte_order: :big]}} =
             Stream.options(
               %{address: address, max_queue_length: 10_000, value_type: :uint16, byte_order: :big},
               5000,
               self()
             )

    for request <- [
          nil,
          %{},
          %{address: address, extra: true},
          %{address: address, receiver: nil},
          %{address: address, mode: :guess},
          %{address: address, max_queue_length: 0},
          %{address: address, max_queue_length: 10_001},
          %{address: address, max_queue_length: true}
        ] do
      assert {:error, %Error{code: :invalid_options}} = Stream.options(request, 5000, self())
    end

    assert {:error, %Error{code: :invalid_value}} =
             Stream.options(%{address: address, value_type: :guess}, 5000, self())

    assert {:error, %Error{code: :invalid_address}} = Stream.options(%{address: %{}}, 5000, self())
  end

  test "WBL-C05 forged subscription field types and extensions are rejected" do
    handle = %Subscription{
      pid: self(),
      reference: make_ref(),
      generation: 1,
      session_reference: make_ref()
    }

    assert Stream.handle?(handle)
    refute inspect(handle) =~ inspect(handle.reference)

    for forged <- [
          nil,
          %{},
          %{handle | pid: nil},
          %{handle | reference: nil},
          %{handle | generation: 0},
          %{handle | generation: 1.0},
          %{handle | session_reference: nil},
          Map.put(handle, :extra, true)
        ] do
      refute Stream.handle?(forged)
    end
  end

  property "WBL-C02 arbitrary flag bytes never allocate atoms or raise" do
    check all(bytes <- binary(max_length: 80)) do
      result = Stream.mode([bytes], :auto)
      assert match?({:ok, _}, result) or match?({:error, %Error{}}, result)
    end
  end
end
