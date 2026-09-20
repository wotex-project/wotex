defmodule Wotex.Workspace.NativeArtifact.CanonicalJSONTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeArtifact.CanonicalJSON

  test "canonicalizes maps, integers, strings and arrays" do
    value = %{"z" => [nil, true, false, -12], "a" => "\b\t\n\f\r\"\\\u0001å"}

    assert CanonicalJSON.encode!(value) ==
             ~S({"a":"\b\t\n\f\r\"\\\u0001å","z":[null,true,false,-12]})
  end

  test "sorts object keys by UTF-16 code units" do
    # U+1F600 starts with the UTF-16 unit D83D, which sorts before U+E000.
    assert CanonicalJSON.encode!(%{"\uE000" => 2, "😀" => 1}) == "{\"😀\":1,\"\uE000\":2}"
  end

  test "map insertion order is irrelevant" do
    left = Map.new([{"b", %{"y" => 2, "x" => 1}}, {"a", 0}])
    right = Map.new([{"a", 0}, {"b", Map.new([{"x", 1}, {"y", 2}])}])

    assert CanonicalJSON.encode!(left) == CanonicalJSON.encode!(right)
  end

  test "rejects floating-point values, non-string keys and invalid UTF-8" do
    assert {:error, message} = CanonicalJSON.encode(%{"value" => 1.0})
    assert message =~ "floating-point"

    assert {:error, message} = CanonicalJSON.encode(%{value: 1})
    assert message =~ "map keys"

    assert {:error, message} = CanonicalJSON.encode(<<255>>)
    assert message =~ "UTF-8"
  end
end
