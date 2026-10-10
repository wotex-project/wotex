defmodule Wotex.Matter.BridgeObservationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.Bridge.Observation
  alias Wotex.Matter.Error

  @generation :binary.copy(<<255>>, 16)
  @maximum 0xFFFFFFFFFFFFFFFF
  @observation %{thing: <<0, 255>>, endpoint: 3, reachable: true, on_off: false, temperature: nil}

  defp receipt(outcome, id \\ 1) do
    %{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => "observation-receipt",
      "generation" => Base.encode16(@generation, case: :lower),
      "id" => Integer.to_string(id),
      "outcome" => outcome
    }
  end

  defp frame(value), do: Jason.encode!(value) <> "\n"

  test "owned opaque Thing, reachability and nullable state retain exact wire roles" do
    for id <- [1, @maximum],
        reachable <- [true, false],
        on_off <- [nil, true, false],
        temperature <- [nil, -32_767, 0, 32_767],
        endpoint <- [3, 65_534] do
      observation = %{
        @observation
        | reachable: reachable,
          on_off: on_off,
          temperature: temperature,
          endpoint: endpoint
      }

      assert {:ok, bytes} = Observation.encode(@generation, id, observation)
      assert byte_size(bytes) <= 1024 and :binary.last(bytes) == 10

      assert Jason.decode!(bytes) == %{
               "v" => 1,
               "backend" => "matter-bridge",
               "type" => "observation",
               "generation" => Base.encode16(@generation, case: :lower),
               "id" => Integer.to_string(id),
               "thing" => "00ff",
               "endpoint" => endpoint,
               "reachable" => reachable,
               "on_off" => on_off,
               "temperature" => temperature
             }
    end

    maximal = %{
      @observation
      | thing: :binary.copy(<<255>>, 256),
        endpoint: 65_534,
        temperature: -32_767
    }

    assert {:ok, bytes} = Observation.encode(@generation, @maximum, maximal)
    assert byte_size(bytes) <= 1024
    assert Jason.decode!(bytes)["thing"] == String.duplicate("ff", 256)
  end

  test "forged values and omitted unavailable fields fail without external error details" do
    invalid = [
      nil,
      [],
      Map.put(@observation, :extra, true),
      %{@observation | thing: <<>>},
      %{@observation | thing: :binary.copy(<<0>>, 257)},
      %{@observation | thing: [0]},
      %{@observation | endpoint: 2},
      %{@observation | endpoint: 65_535},
      %{@observation | endpoint: 3.0},
      %{@observation | reachable: nil},
      %{@observation | reachable: 1},
      %{@observation | on_off: 0},
      %{@observation | temperature: -32_768},
      %{@observation | temperature: 32_768},
      %{@observation | temperature: 0.0},
      %{@observation | temperature: true}
    ]

    for observation <- invalid ++ Enum.map(Map.keys(@observation), &Map.delete(@observation, &1)) do
      assert {:error, %Error{code: :invalid_frame, details: %{}}} =
               Observation.encode(@generation, 1, observation)
    end

    for {generation, id} <- [
          {nil, 1},
          {<<0>>, 1},
          {@generation, 0},
          {@generation, -1},
          {@generation, @maximum + 1},
          {@generation, "1"},
          {@generation, 1.0}
        ] do
      assert {:error, %Error{code: :invalid_frame}} =
               Observation.encode(generation, id, @observation)
    end
  end

  test "receipts bind exact generation, decimal identity and the two fixed outcomes" do
    for {name, outcome} <- [{"applied", :applied}, {"refused", :refused}], id <- [1, @maximum] do
      value = receipt(name, id)
      assert {:ok, ^outcome} = Observation.decode_receipt(frame(value), @generation, id)

      for invalid <- [
            Map.put(value, "v", 1.0),
            Map.put(value, "type", "result"),
            Map.put(value, "backend", "matter-native"),
            Map.put(value, "outcome", "completed"),
            Map.put(value, "id", id),
            Map.put(value, "id", "0" <> Integer.to_string(id)),
            Map.put(value, "id", Integer.to_string(id + 1)),
            Map.put(value, "generation", String.duplicate("0", 32)),
            Map.put(value, "generation", String.upcase(value["generation"])),
            Map.put(value, "extra", false),
            Map.delete(value, "outcome")
          ] do
        assert {:error, %Error{code: :invalid_frame, details: %{}}} =
                 Observation.decode_receipt(frame(invalid), @generation, id)
      end
    end
  end

  test "receipt framing, scalar shape, decoded duplicates and complete byte bound are enforced" do
    bytes = frame(receipt("applied"))
    body = binary_part(bytes, 0, byte_size(bytes) - 1)
    padded = body <> String.duplicate(" ", 511 - byte_size(body)) <> "\n"
    assert byte_size(padded) == 512
    assert {:ok, :applied} = Observation.decode_receipt(padded, @generation, 1)

    for invalid <- [
          padded <> " ",
          body,
          body <> "\r\n",
          "\n" <> bytes,
          <<0>> <> bytes,
          bytes <> "{}\n",
          frame([receipt("applied")]),
          frame(Map.put(receipt("applied"), "outcome", %{})),
          String.replace(bytes, "\"v\":1", "\"v\":1,\"v\":1"),
          String.replace(bytes, "\"v\":1", "\"v\":1,\"\\u0076\":1"),
          <<255, 10>>,
          nil
        ] do
      assert {:error, %Error{code: :invalid_frame}} =
               Observation.decode_receipt(invalid, @generation, 1)
    end

    for {generation, id} <- [
          {nil, 1},
          {<<0>>, 1},
          {@generation, 0},
          {@generation, @maximum + 1},
          {@generation, "1"}
        ] do
      assert {:error, %Error{code: :invalid_frame}} =
               Observation.decode_receipt(bytes, generation, id)
    end
  end
end
