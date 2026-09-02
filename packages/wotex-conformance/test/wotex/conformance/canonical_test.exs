defmodule Wotex.Conformance.CanonicalTest do
  use ExUnit.Case, async: true

  alias Wotex.Conformance.Canonical

  test "orders object keys recursively and produces stable bytes" do
    left = %{"z" => [%{"b" => 2, "a" => 1}], "a" => true}
    right = Map.new([{"a", true}, {"z", [Map.new([{"a", 1}, {"b", 2}])]}])

    assert {:ok, encoded_left} = Canonical.encode(left)
    assert {:ok, encoded_right} = Canonical.encode(right)
    assert encoded_left == ~s({"a":true,"z":[{"a":1,"b":2}]})
    assert encoded_left == encoded_right
    assert Canonical.digest(left) == Canonical.digest(right)
  end

  test "rejects non-string object keys and non-JSON values" do
    assert {:error, %{code: :invalid_map_key}} = Canonical.encode(%{atom: "value"})
    assert {:error, %{code: :invalid_type}} = Canonical.encode({:tuple, "value"})
  end

  test "uses a lowercase tagged SHA-256 digest" do
    assert {:ok, digest} = Canonical.digest(%{"value" => 1})
    assert Canonical.valid_digest?(digest)
    refute Canonical.valid_digest?(String.upcase(digest))
  end
end
