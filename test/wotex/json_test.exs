defmodule Wotex.JSONTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.{Error, JSON}

  property "canonical encoding preserves generated JSON scalar maps and lists" do
    check all(
            entries <- list_of(tuple({json_key(), json_scalar()}), max_length: 20),
            values <- list_of(json_scalar(), max_length: 20)
          ) do
      value = %{"object" => Map.new(entries), "list" => values}

      assert {:ok, encoded} = JSON.encode(value)
      assert Jason.decode!(encoded) == value
      assert {:ok, ^encoded} = JSON.encode(value)
    end
  end

  test "rejects non-JSON values before encoding" do
    assert {:error, %Error{code: :invalid_json_value, path: "/0"}} =
             JSON.validate([self()])

    assert {:error, %Error{code: :invalid_string, phase: :value, path: "/value"}} =
             JSON.encode(%{"value" => <<255>>})
  end

  test "rejects invalid UTF-8 strings and object keys without leaking invalid paths" do
    for bytes <- [<<255>>, <<0xC0, 0xAF>>, <<0xED, 0xA0, 0x80>>, <<0xF0, 0x90>>] do
      assert {:error, %Error{code: :invalid_string, path: "/nested/0"}} =
               JSON.validate(%{"nested" => [bytes]})

      assert {:error, %Error{code: :invalid_string, path: "/nested"} = error} =
               JSON.validate(%{"nested" => %{bytes => true}})

      assert String.valid?(error.path)
    end
  end

  test "preserves valid Unicode strings and keys byte for byte" do
    value = %{"温度" => ["å", "é", "\u0000", "𝄞"]}
    assert :ok = JSON.validate(value)
    assert {:ok, encoded} = JSON.encode(value)
    assert Jason.decode!(encoded) == value
  end

  test "escapes JSON Pointer path segments" do
    assert JSON.pointer_segment("a~/b") == "a~0~1b"
  end

  defp json_key do
    string(:alphanumeric, min_length: 1, max_length: 16)
  end

  defp json_scalar do
    one_of([
      constant(nil),
      boolean(),
      integer(),
      float(min: -1.0e6, max: 1.0e6),
      string(:printable, max_length: 24)
    ])
  end
end
