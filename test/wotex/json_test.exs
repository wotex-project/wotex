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

  test "rejects non-JSON values and reports encoding failures" do
    assert {:error, %Error{code: :invalid_json_value, path: "/0"}} =
             JSON.validate([self()])

    assert {:error, %Error{code: :encode_failed, phase: :encode}} =
             JSON.encode(%{"value" => <<255>>})
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
