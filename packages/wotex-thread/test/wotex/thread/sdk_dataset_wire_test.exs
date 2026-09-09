defmodule Wotex.Thread.SdkDatasetWireTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Thread.{Dataset, Error}
  alias Wotex.Thread.OpenThread.DatasetWire

  @moduletag requirements: ["WTH-S01", "WTH-C02", "WTH-C07"], vectors: ["WTH-V02"]

  test "typed Dataset serialization preserves unknown fields and validates both kinds" do
    {:ok, dataset} = Dataset.decode(<<250, 3, 0, 255, 42>>)

    for kind <- [:active, :pending] do
      assert {:ok, parameters} = DatasetWire.parameters(dataset, kind)
      assert parameters.kind == Atom.to_string(kind)

      assert {:ok, ^dataset} =
               DatasetWire.decode(%{"type" => "bytes", "base64" => parameters.dataset.base64})

      assert {:ok, %{kind: value}} = DatasetWire.selector(kind)
      assert value == Atom.to_string(kind)
    end

    assert {:error, %Error{code: :invalid_dataset_kind}} = DatasetWire.parameters(dataset, :unknown)

    for forged <- [nil, Map.put(dataset, :extra, :untrusted), %{dataset | types: []}] do
      assert {:error, %Error{code: :invalid_dataset}} = DatasetWire.parameters(forged, :active)
    end
  end

  test "malformed binary envelopes are bounded, canonical and credential-free" do
    canary = "private-canary"

    for value <- [
          nil,
          %{},
          %{"type" => "bytes", "base64" => nil},
          %{"type" => "bytes", "base64" => canary},
          %{"type" => "bytes", "base64" => "AA==", "extra" => true},
          %{"type" => "text", "base64" => ""},
          %{"type" => "bytes", "base64" => "A A=="},
          %{"type" => "bytes", "base64" => "AB=="},
          %{"type" => "bytes", "base64" => Base.encode64(<<250, 253, 0::size(2024)>>)},
          %{"type" => "bytes", "base64" => String.duplicate("A", 341)},
          %{"type" => "bytes", "base64" => Base.encode64(<<5, 16, 1>>)}
        ] do
      assert {:error, %Error{code: :invalid_dataset} = error} = DatasetWire.decode(value)
      refute inspect(error) =~ canary
    end
  end

  property "binary envelope roundtrips every bounded opaque TLV without interpretation" do
    check all(bytes <- binary(max_length: 252)) do
      {:ok, dataset} = Dataset.decode(<<250, byte_size(bytes), bytes::binary>>)
      {:ok, %{dataset: envelope}} = DatasetWire.parameters(dataset, :active)

      assert {:ok, ^dataset} =
               DatasetWire.decode(%{"type" => envelope.type, "base64" => envelope.base64})
    end
  end
end
