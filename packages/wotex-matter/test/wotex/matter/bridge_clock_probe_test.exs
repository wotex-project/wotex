defmodule Wotex.Matter.BridgeClockProbeTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Matter.Bridge.{ClockProbe, ClockProjection}
  alias Wotex.Matter.Error

  @generation :binary.copy(<<1>>, 16)
  @uint64 0xFFFFFFFFFFFFFFFF

  defp object(id \\ 1, native \\ "0") do
    %{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => "clock-sample",
      "generation" => Base.encode16(@generation, case: :lower),
      "id" => Integer.to_string(id),
      "native_ms" => native
    }
  end

  defp frame(value), do: Jason.encode!(value) <> "\n"

  test "probe identities and native time preserve full widths without equating clock domains" do
    for id <- [1, @uint64], native <- [0, @uint64] do
      assert {:ok, bytes} = ClockProbe.encode(@generation, id)
      encoded = Jason.decode!(bytes)
      assert map_size(encoded) == 5 and byte_size(bytes) <= 512 and String.ends_with?(bytes, "\n")
      assert encoded["type"] == "clock-probe" and encoded["id"] == Integer.to_string(id)
      assert encoded["generation"] == Base.encode16(@generation, case: :lower)

      assert {:ok, ^native} =
               ClockProbe.decode(frame(object(id, Integer.to_string(native))), @generation, id)
    end

    assert {:ok, sample} = ClockProbe.decode(frame(object(1, "100")), @generation, 1)
    assert {:ok, projection} = ClockProjection.new(@generation, -1000, -990, sample, {98, 100})
    assert {:ok, -512} = ClockProjection.deadline(projection, @generation, 600, -980)
  end

  test "exact fields, roles, types, correlation and canonical time are required" do
    valid = object()

    invalid =
      Enum.flat_map(Map.keys(valid), fn key ->
        [Map.delete(valid, key) | Enum.map([nil, true, [], %{}], &Map.put(valid, key, &1))]
      end) ++
        [
          Map.put(valid, "extra", 1),
          %{valid | "v" => 1.0},
          %{valid | "backend" => "matter-native"},
          %{valid | "type" => "clock-probe"},
          %{valid | "generation" => String.duplicate("ff", 16)},
          %{valid | "id" => "2"},
          %{valid | "id" => "01"}
        ] ++
        Enum.map(["", "00", "+1", "-1", "1.0", "1 ", "18446744073709551616"], fn time ->
          %{valid | "native_ms" => time}
        end)

    for value <- invalid,
        do:
          assert(
            {:error, %Error{code: :invalid_frame, details: %{}}} =
              ClockProbe.decode(frame(value), @generation, 1)
          )

    body = Jason.encode!(valid)

    for {key, value} <- valid do
      duplicate =
        String.trim_trailing(body, "}") <>
          "," <> Jason.encode!(key) <> ":" <> Jason.encode!(value) <> "}\n"

      assert {:error, %Error{}} = ClockProbe.decode(duplicate, @generation, 1)
    end

    for bytes <- [
          body,
          body <> "\r\n",
          body <> "\n\n",
          body <> "{}\n",
          body <> <<0, 10>>,
          <<255, 10>>
        ],
        do: assert({:error, %Error{}} = ClockProbe.decode(bytes, @generation, 1))

    boundary = body <> String.duplicate(" ", 511 - byte_size(body)) <> "\n"
    assert byte_size(boundary) == 512
    assert {:ok, 0} = ClockProbe.decode(boundary, @generation, 1)
    assert {:error, %Error{}} = ClockProbe.decode(" " <> boundary, @generation, 1)

    for id <- [nil, 0, -1, 1.0, "1", @uint64 + 1] do
      assert {:error, %Error{}} = ClockProbe.encode(@generation, id)
      assert {:error, %Error{}} = ClockProbe.decode(frame(valid), @generation, id)
    end

    for generation <- [nil, <<>>, :binary.copy(<<1>>, 15), :binary.copy(<<1>>, 17)] do
      assert {:error, %Error{}} = ClockProbe.encode(generation, 1)
      assert {:error, %Error{}} = ClockProbe.decode(frame(valid), generation, 1)
    end
  end

  property "arbitrary frame terms return a detail-free error without creating resources" do
    check all(value <- term()) do
      assert {:error, %Error{details: %{}}} = ClockProbe.decode(value, @generation, 1)
    end
  end
end
