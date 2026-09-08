defmodule Wotex.Thread.DatasetTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Thread.{Daemon, Dataset}

  test "dataset known widths, unknown TLVs, credentials and completeness" do
    entries = [
      {0, <<0, 0, 15>>},
      {1, <<1, 2>>},
      {2, <<0::64>>},
      {3, "mesh"},
      {5, "secret-key-16byt"},
      {7, <<0::64>>},
      {12, <<0, 0, 0, 0>>},
      {14, <<0::64>>},
      {53, <<0, 4, 0, 0, 255, 255>>},
      {240, "extension"}
    ]

    bytes = for {type, value} <- entries, into: <<>>, do: <<type, byte_size(value), value::binary>>
    assert {:ok, dataset} = Dataset.decode(bytes)
    assert dataset.entries == entries
    refute inspect(dataset) =~ "secret"
    assert Dataset.complete?(dataset, :active)
    refute Dataset.complete?(dataset, :pending)
    assert {:ok, ^bytes} = Dataset.encode(dataset)
    pending = bytes <> <<51, 8, 0::64, 52, 4, 0::32>>
    assert {:ok, dataset} = Dataset.decode(pending)
    assert Dataset.complete?(dataset, :pending)
    refute Dataset.complete?(dataset, :active)

    for bytes <- [
          <<0>>,
          <<0, 3, 0>>,
          <<3, 0>>,
          <<3, 1, 255>>,
          <<3, 1, 0>>,
          <<5, 1, 0>>,
          <<240, 0, 240, 0>>,
          :binary.copy(<<0>>, 255)
        ],
        do: assert(match?({:error, _}, Dataset.decode(bytes)))

    for entries <- [
          [:bad],
          [{256, ""}],
          [{240, :binary.copy("x", 253)}],
          List.duplicate({240, "x"}, 100)
        ],
        do: assert(match?({:error, _}, Dataset.encode(%Dataset{entries: entries, types: []})))

    assert {:error, _} = Dataset.encode(nil)
  end

  test "daemon output distinguishes completion from errors and incomplete frames" do
    assert {:ok, "leader"} = Daemon.parse("> leader\r\nDone\r\n> ")
    assert {:ok, ""} = Daemon.parse("Done\n")
    assert :more = Daemon.parse("leader\nDo")
    assert :more = Daemon.parse(<<0xC3>>)
    assert {:ok, "é"} = Daemon.parse(<<0xC3, 0xA9, "\nDone\n">>)

    for bytes <- ["Error 7: InvalidArgs\nDone\n", <<255>>, :binary.copy("x", 8193), nil],
        do: assert(match?({:error, _}, Daemon.parse(bytes)))
  end

  property "dataset parser never raises and successful values round trip exactly" do
    check all(bytes <- binary(max_length: 280)) do
      case Dataset.decode(bytes) do
        {:ok, dataset} -> assert {:ok, ^bytes} = Dataset.encode(dataset)
        {:error, _} -> :ok
      end
    end
  end
end
