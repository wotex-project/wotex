defmodule Wotex.Matter.BridgeControlTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.Bridge.Control
  alias Wotex.Matter.Error

  @generation <<255::128>>
  @revision "250a9e6c50ee2068107f3c4808b680f5f2925415"
  @model "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671"

  defp receipt(type) do
    base = %{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => Atom.to_string(type),
      "generation" => Base.encode16(@generation, case: :lower)
    }

    if type == :ready,
      do: Map.merge(base, %{"sdk_revision" => @revision, "model_sha256" => @model}),
      else: base
  end

  defp frame(value), do: Jason.encode!(value) <> "\n"

  test "open and close are exact four-field controls for one binary generation" do
    for type <- [:open, :close] do
      assert {:ok, bytes} = Control.encode(type, @generation)
      assert String.ends_with?(bytes, "\n") and byte_size(bytes) <= 512
      assert Jason.decode!(bytes) == receipt(type)
    end

    for {type, generation} <- [
          {:ready, @generation},
          {"open", @generation},
          {:open, <<0>>},
          {:open, nil}
        ] do
      assert {:error, %Error{code: :invalid_frame, details: %{}}} = Control.encode(type, generation)
    end
  end

  test "ready and closed require exact fields, generation and pinned receipts" do
    for type <- [:ready, :closed] do
      value = receipt(type)
      assert :ok = Control.decode(frame(value), type, @generation)

      for invalid <- [
            Map.put(value, "v", 1.0),
            Map.put(value, "v", "1"),
            Map.put(value, "generation", String.duplicate("0", 32)),
            Map.put(value, "generation", String.upcase(value["generation"])),
            Map.put(value, "backend", "matter-native"),
            Map.put(value, "extra", nil),
            Map.delete(value, "type"),
            Map.put(value, "type", "open")
          ] do
        assert {:error, %Error{code: :invalid_frame}} =
                 Control.decode(frame(invalid), type, @generation)
      end
    end

    for field <- ["sdk_revision", "model_sha256"] do
      invalid =
        Map.put(receipt(:ready), field, String.duplicate("0", byte_size(receipt(:ready)[field])))

      assert {:error, %Error{code: :invalid_frame}} =
               Control.decode(frame(invalid), :ready, @generation)
    end
  end

  test "LF framing, duplicate fields and the complete 512-byte limit are enforced" do
    bytes = frame(receipt(:ready))
    body = binary_part(bytes, 0, byte_size(bytes) - 1)
    padded = body <> String.duplicate(" ", 511 - byte_size(body)) <> "\n"
    assert byte_size(padded) == 512
    assert :ok = Control.decode(padded, :ready, @generation)

    for invalid <- [
          padded <> "\n",
          body,
          body <> "\r\n",
          "\n" <> bytes,
          "\r" <> bytes,
          <<0>> <> bytes,
          String.replace(bytes, "\"v\":1", "\"v\":1,\"v\":1"),
          frame([receipt(:ready)]),
          frame(Map.put(receipt(:ready), "type", %{})),
          <<255, 10>>,
          nil
        ] do
      assert {:error, %Error{code: :invalid_frame, details: %{}}} =
               Control.decode(invalid, :ready, @generation)
    end
  end
end
