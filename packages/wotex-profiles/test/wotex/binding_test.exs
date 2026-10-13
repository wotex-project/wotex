defmodule Wotex.Profiles.BindingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Binding, Error}
  alias Wotex.Profiles.Test.Fixtures, as: F

  test "independent registration identity matches all public reconstruction seams" do
    original = F.json("installed-binding")
    assert {:ok, digest} = Binding.digest(Map.delete(original, "sha256"), F.limits())
    assert digest == original["sha256"]
    assert {:ok, binding} = Binding.new(original, F.limits())
    assert {:ok, ^binding} = Binding.new(binding, F.limits())
    assert {:ok, ^original} = Binding.to_map(binding, F.limits())
    assert {:ok, reference} = Binding.reference(binding, F.limits())
    assert reference == F.json("capture")["binding"]
  end

  test "changed schema, operation, capture or decoder cannot reuse a contract identity" do
    original = F.json("installed-binding")

    for changed <- [
          put_in(original, ["selector_schema", "properties", "register", "maximum"], 100),
          Map.put(original, "operations", ["readproperty", "writeproperty"]),
          Map.put(original, "capture_fields", ["model", "revision"]),
          put_in(original, ["raw_value_contract", "sha256"], String.duplicate("c", 64))
        ] do
      assert {:error, %Error{code: :reference_conflict}} = Binding.new(changed, F.limits())
      assert {:ok, digest} = Binding.digest(Map.delete(changed, "sha256"), F.limits())
      refute digest == original["sha256"]
      assert {:ok, _} = Binding.new(Map.put(changed, "sha256", digest), F.limits())
    end
  end

  test "installed grammars are closed and unsupported mechanics never select code" do
    original = Map.delete(F.json("installed-binding"), "sha256")

    for {field, value} <- [
          {"operations", []},
          {"operations", nil},
          {"operations", ["unknown"]},
          {"operations", ["writeproperty", "readproperty"]},
          {"capture_fields", nil},
          {"capture_fields", List.duplicate("model", 65)},
          {"capture_fields", ["model", "model"]},
          {"capture_fields", ["model/secret"]},
          {"selector_schema", %{"type" => "integer"}},
          {"selector_schema",
           %{"type" => "object", "properties" => %{}, "additionalProperties" => true}},
          {"raw_value_schema", %{"type" => "bytes"}},
          {"raw_value_contract", %{}},
          {"codec_contracts", [%{}]}
        ] do
      assert {:error, %Error{}} = Binding.digest(Map.put(original, field, value), F.limits())
    end

    for data <- [
          Map.put(original, "module", "Secret.Decoder"),
          %{},
          URI.new!("urn:example:foreign")
        ] do
      assert {:error, %Error{}} = Binding.digest(data, F.limits())
    end

    assert {:error, %Error{}} = Binding.digest(original, nil)

    assert {:error, %Error{code: :input_limit}} =
             Binding.digest(original, Map.put(F.limits(), "max_nodes", 1))

    assert {:error, %Error{}} = Binding.new(Map.put(original, "sha256", "bad"), F.limits())
    assert {:ok, binding} = Binding.new(F.json("installed-binding"), F.limits())
    assert {:error, %Error{}} = Binding.new(Map.put(binding, :foreign, "secret"), F.limits())
    assert {:ok, _} = Binding.digest(Map.put(original, "capture_fields", []), F.limits())

    assert {:ok, _} =
             Binding.digest(Map.put(original, "operations", ["readallproperties"]), F.limits())
  end
end
