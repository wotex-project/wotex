defmodule Wotex.JSONTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.{Error, JSON}

  test "a tiny node budget does not traverse a large remaining array" do
    values = List.duplicate(nil, 100_000)
    assert :ok = JSON.validate([])
    {:reductions, before} = Process.info(self(), :reductions)

    assert {:error, %Error{code: :node_limit_exceeded, path: "/1"}} =
             JSON.validate(values, max_nodes: 2)

    {:reductions, after_validation} = Process.info(self(), :reductions)

    # Work-bound regression, not a wall-clock performance threshold. The eager
    # indexed-list implementation consumes over 100,000 reductions here.
    assert after_validation - before < 10_000
  end

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

  test "WTX.03 rejects top-level and nested structs without invoking Enumerable" do
    for value <- [
          %Wotex.Form{value: nil},
          ~D[2026-01-01],
          MapSet.new([1]),
          1..3,
          %{__struct__: UnknownJSONStruct, secret: "private-canary"}
        ] do
      assert {:error, %Error{code: :invalid_json_value, phase: :value, path: "/"}} =
               JSON.validate(value)

      assert {:error, %Error{code: :invalid_json_value, path: "/nested/0"} = error} =
               JSON.encode(%{"nested" => [value]})

      refute inspect(error) =~ "private-canary"
    end

    assert {:error, %Error{code: :invalid_json_value}} = Wotex.Form.new(%Wotex.Form{value: nil})
    value = %{"__struct__" => "extension", "value" => true}
    assert :ok = JSON.validate(value)
    assert {:ok, bytes} = JSON.encode(value)
    assert Jason.decode!(bytes) == value
  end

  property "WTX.03 rejects improper arrays at their containing path without raising" do
    check all(
            values <- list_of(json_scalar(), max_length: 20),
            tail <- one_of([constant(:invalid_tail), binary(), integer(), constant(%{})])
          ) do
      improper = Enum.reduce(Enum.reverse([nil | values]), tail, fn item, rest -> [item | rest] end)

      assert {:error, %Error{code: :invalid_json_value, path: "/nested"}} =
               JSON.validate(%{"nested" => improper})

      assert {:error, %Error{code: :invalid_json_value}} = JSON.encode(improper)
    end
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

  test "decodes under explicit limits with copied strings and no duplicate members" do
    source = ~s({"title":"Lamp","tags":["a","b"],"nested":{"k":1.5}})
    assert {:ok, decoded} = JSON.decode(source)
    assert decoded == %{"title" => "Lamp", "tags" => ["a", "b"], "nested" => %{"k" => 1.5}}
    assert :binary.referenced_byte_size(decoded["title"]) < byte_size(source)

    assert {:error, %Error{code: :duplicate_member, phase: :parse, path: "/title"}} =
             JSON.decode(~s({"title":"a","title":"b"}))

    assert {:error, %Error{code: :duplicate_member, path: "/nested/k"}} =
             JSON.decode(~s({"nested":{"k":1,"k":2}}))
  end

  test "bounds depth and string size before decoding" do
    hostile_depth = String.duplicate("[", 100_000)

    assert {:error, %Error{code: :depth_limit_exceeded, phase: :parse}} =
             JSON.decode(hostile_depth, max_depth: 8)

    assert {:ok, [[[]]]} = JSON.decode("[[[]]]", max_depth: 3)
    assert {:error, %Error{code: :depth_limit_exceeded}} = JSON.decode("[[[[]]]]", max_depth: 3)

    long = ~s(["#{String.duplicate("x", 32)}"])

    assert {:error, %Error{code: :string_limit_exceeded, phase: :parse}} =
             JSON.decode(long, max_string_bytes: 16)

    assert {:ok, _} = JSON.decode(long, max_string_bytes: 32)

    escaped = ~S({"k\"ey":"v"})
    assert {:ok, %{"k\"ey" => "v"}} = JSON.decode(escaped)
  end

  test "rejects oversized, invalid, and non-binary sources" do
    assert {:error, %Error{code: :byte_limit_exceeded, phase: :parse, details: %{max_bytes: 4}}} =
             JSON.decode("[1,2,3]", max_bytes: 4)

    assert {:error, %Error{code: :invalid_string, phase: :parse}} = JSON.decode(<<?", 255, ?">>)
    assert {:error, %Error{code: :invalid_json, phase: :parse}} = JSON.decode("{")
    assert {:error, %Error{code: :invalid_input}} = JSON.decode(:atom)
    assert {:error, %Error{code: :invalid_json}} = JSON.decode(~S(["unterminated))
    assert {:error, %Error{code: :invalid_options}} = JSON.validate(%{}, :bad)

    assert {:error, %Error{code: :invalid_limit, details: %{option: :max_depth}}} =
             JSON.decode("[]", max_depth: -1)
  end

  test "bounds collection size and node count during and after decoding" do
    assert {:error, %Error{code: :collection_limit_exceeded, path: "/"}} =
             JSON.decode("[1,2,3,4]", max_collection_size: 3)

    assert {:error, %Error{code: :collection_limit_exceeded, path: "/o"}} =
             JSON.validate(%{"o" => %{"a" => 1, "b" => 2}}, max_collection_size: 1)

    assert {:error, %Error{code: :collection_limit_exceeded, path: "/l"}} =
             JSON.validate(%{"l" => [1, 2]}, max_collection_size: 1)

    assert {:error, %Error{code: :node_limit_exceeded}} = JSON.decode("[1,2,3,4]", max_nodes: 3)
  end

  test "bounds native string payload bytes and string size" do
    assert {:error, %Error{code: :byte_limit_exceeded, phase: :value, path: "/b"}} =
             JSON.validate(%{"a" => "12345", "b" => "6789"}, max_bytes: 8)

    assert :ok = JSON.validate(%{"a" => "12345", "b" => "678"}, max_bytes: 10)

    assert {:error, %Error{code: :string_limit_exceeded, phase: :value, path: "/a"}} =
             JSON.validate(%{"a" => "12345"}, max_string_bytes: 4)
  end

  test "resolves RFC 6901 pointers against decoded values" do
    value = %{"a/b" => [%{"m~n" => "hit"}]}
    assert {:ok, "hit"} = JSON.resolve_pointer(value, "/a~1b/0/m~0n")
    assert {:ok, ^value} = JSON.resolve_pointer(value, "")
    assert :error = JSON.resolve_pointer(value, "/a~1b/1")
    assert :error = JSON.resolve_pointer(value, "a/b")
    assert :error = JSON.resolve_pointer(%{"a" => 1}, "/a/b")
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
