defmodule Wotex.BACnet.ValueTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.Value

  test "declared scalars map to native tags and back without guessing" do
    for {name, value} <- [
          {"Null", nil},
          {"Boolean", true},
          {"Signed", -42},
          {"Unsigned", 42},
          {"Real", 1.5},
          {"Double", 1.5},
          {"String", "héllo"},
          {"OctetString", <<255>>}
        ] do
      assert {:ok, encoded} = Value.encode(value, %{"@type" => "bacv:" <> name})
      assert {^value, %{bacnet_type: _}} = Value.result(encoded)
      assert {:ok, ^encoded} = Value.encode(encoded, nil)
    end

    for {name, value} <- [
          {"Real", 1.0e100},
          {"Boolean", 1},
          {"Signed", 2_147_483_648},
          {"Unsigned", -1},
          {"String", <<255>>},
          {"OctetString", String.duplicate("x", 4097)},
          {"Unknown", 1}
        ],
        do: assert(match?({:error, _}, Value.encode(value, %{"@type" => "bacv:" <> name})))

    assert {:error, _} = Value.encode(42, nil)
    assert {:error, _} = Value.encode(42, %{})
    unknown = Encoding.create!({:enumerated, 1234})
    assert {^unknown, %{native_value: true}} = Value.result(unknown)
    assert {:written, %{}} = Value.result(:written)
  end
end
