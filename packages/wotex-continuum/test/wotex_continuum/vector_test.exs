defmodule WotexContinuum.VectorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexContinuum.{Capability, Codec, Compatibility, Error}

  @vectors Path.expand("../vectors", __DIR__)

  test "every valid vector decodes and round-trips through canonical bytes" do
    for path <- Path.wildcard(Path.join([@vectors, "valid", "*.json"])) do
      source = File.read!(path)

      assert {:ok, value} = Codec.decode(source), path
      assert {:ok, first} = Codec.encode(value, canonical: true), path
      assert {:ok, decoded} = Codec.decode(first), path
      assert {:ok, second} = Codec.encode(decoded, canonical: true), path
      assert first == second, path
    end
  end

  test "every registered struct is revalidated before construction or encoding" do
    required_fields = %{
      "action_intent" => :intent_id,
      "action_result" => :result_id,
      "capability" => :id,
      "compatibility" => :schema_requirement,
      "continuum_manifest" => :manifest_id,
      "degradation" => :degradation_id,
      "delivery" => :delivery_id,
      "evidence_reference" => :evidence_id,
      "execution_context" => :execution_id,
      "exit_receipt" => :receipt_id,
      "lifecycle" => :subject_id,
      "mode" => :deployment,
      "observation_proposal" => :proposal_id
    }

    for path <- Path.wildcard(Path.join([@vectors, "valid", "*.json"])) do
      source = File.read!(path)
      assert {:ok, value} = Codec.decode(source), path
      module = value.__struct__

      assert {:ok, ^value} = module.new(value), path

      field = Map.fetch!(required_fields, module.kind())
      tampered = Map.put(value, field, nil)

      assert {:error, %Error{}} = module.new(tampered), path
      assert {:error, %Error{}} = WotexContinuum.to_map(tampered), path
      assert {:error, %Error{}} = Codec.encode(tampered), path
    end
  end

  test "every invalid vector returns its exact code and path" do
    for path <- Path.wildcard(Path.join([@vectors, "invalid", "*.json"])) do
      vector =
        path
        |> File.read!()
        |> Jason.decode!()

      source = Jason.encode!(vector["input"])

      assert {:error, %Error{} = error} = Codec.decode(source), path
      assert Atom.to_string(error.code) == vector["expected"]["code"], path
      assert Atom.to_string(error.phase) == vector["expected"]["phase"], path
      assert error.path == vector["expected"]["path"], path
    end
  end

  test "canonical vectors match exact bytes" do
    for path <- Path.wildcard(Path.join([@vectors, "canonical", "*.json"])) do
      vector =
        path
        |> File.read!()
        |> Jason.decode!()

      assert {:ok, value} = WotexContinuum.from_map(vector["input"]), path

      for _ <- 1..20 do
        assert {:ok, canonical} = Codec.encode(value, canonical: true), path
        assert canonical == vector["canonical"], path
      end
    end
  end

  test "compatibility vectors report all declared outcomes" do
    for path <- Path.wildcard(Path.join([@vectors, "compatibility", "*.json"])) do
      vector =
        path
        |> File.read!()
        |> Jason.decode!()

      assert {:ok, requirements} = Compatibility.new(vector["requirements"]), path

      capabilities =
        Enum.map(vector["capabilities"], fn map ->
          assert {:ok, capability} = Capability.new(map), path
          capability
        end)

      case vector["expected"] do
        "compatible" ->
          assert :ok =
                   Compatibility.evaluate(
                     requirements,
                     vector["actual_schema_version"],
                     capabilities
                   ),
                 path

        expected_types ->
          assert {:error, mismatches} =
                   Compatibility.evaluate(
                     requirements,
                     vector["actual_schema_version"],
                     capabilities
                   ),
                 path

          assert Enum.map(mismatches, &Atom.to_string(&1.type)) == expected_types, path
      end
    end
  end
end
