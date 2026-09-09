defmodule Wotex.Conformance.ObservationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.Observation

  @operation "thing_description.parse"

  test "document operations are a closed list" do
    assert Observation.operations() == [
             "thing_description.parse",
             "thing_description.validate",
             "thing_model.parse",
             "thing_model.validate"
           ]

    assert Enum.all?(Observation.operations(), &Observation.document_operation?/1)
    refute Observation.document_operation?("thing_description.serialize")
  end

  test "other operations carry no normalized shape" do
    assert Observation.validate_input("codec.encode", %{"bytes" => "AA"}) ==
             {:ok, %{"bytes" => "AA"}}

    assert Observation.validate("codec.encode", ["anything"]) == {:ok, ["anything"]}
  end

  test "declared input requires one document and one bounded projection" do
    assert {:ok, _} =
             Observation.validate_input(@operation, %{
               "document" => %{"title" => "Thing"},
               "projection" => ["/title", "/properties/a~1b/0"]
             })

    assert {:ok, _} =
             Observation.validate_input(@operation, %{"document" => %{}, "projection" => []})

    invalid = [
      {"document must exist", %{"projection" => []}, :invalid_vector_input},
      {"members are closed", %{"document" => %{}, "projection" => [], "extra" => 1},
       :invalid_vector_input},
      {"input is an object", ["document"], :invalid_vector_input},
      {"document is an object", %{"document" => "text", "projection" => []}, :invalid_document},
      {"projection is a list", %{"document" => %{}, "projection" => "/title"}, :invalid_projection},
      {"pointers are rooted", %{"document" => %{}, "projection" => ["title"]}, :invalid_projection},
      {"pointers are not empty", %{"document" => %{}, "projection" => [""]}, :invalid_projection},
      {"pointers escape correctly", %{"document" => %{}, "projection" => ["/a~2b"]},
       :invalid_projection},
      {"pointers are bounded", %{"document" => %{}, "projection" => ["/" <> long()]},
       :invalid_projection},
      {"pointers are unique", %{"document" => %{}, "projection" => ["/a", "/a"]},
       :invalid_projection},
      {"projection is bounded", %{"document" => %{}, "projection" => pointers(65)},
       :invalid_projection}
    ]

    for {reason, input, code} <- invalid do
      assert {:error, %{code: ^code}} = Observation.validate_input(@operation, input), reason
    end
  end

  test "an accepted observation reports exactly its projected document" do
    assert {:ok, _} =
             Observation.validate(@operation, %{
               "accepted" => true,
               "document" => %{"/title" => "Thing"}
             })

    assert {:error, %{code: :invalid_observation, phase: :protocol}} =
             Observation.validate(@operation, %{"accepted" => "yes"})

    assert {:error, %{code: :invalid_observation}} =
             Observation.validate(@operation, %{"accepted" => true, "errors" => []})

    assert {:error, %{code: :invalid_document}} =
             Observation.validate(@operation, %{"accepted" => true, "document" => []})
  end

  test "a rejected observation lists unique bounded errors sorted by path and code" do
    assert {:ok, _} =
             Observation.validate(@operation, %{
               "accepted" => false,
               "errors" => [
                 error("schema_violation", "schema", "/security"),
                 error("undefined_security_reference", "semantic", "/security"),
                 error("empty_title", "semantic", "/title")
               ]
             })

    invalid = [
      {"errors are a list", "none", :invalid_observation},
      {"errors are not empty", [], :invalid_observation},
      {"errors are objects", ["schema_violation"], :invalid_observation},
      {"error members are closed", [Map.put(error("a", "b", "/c"), "message", "text")],
       :invalid_observation},
      {"codes are identifiers", [error("Schema Violation", "schema", "/title")],
       :invalid_observation},
      {"phases are identifiers", [error("schema_violation", "Schema", "/title")],
       :invalid_observation},
      {"paths are pointers", [error("schema_violation", "schema", "title")], :invalid_observation},
      {"errors are unique",
       [error("empty_title", "semantic", "/title"), error("empty_title", "semantic", "/title")],
       :unsorted_observation_errors},
      {"errors are sorted",
       [error("empty_title", "semantic", "/title"), error("a", "semantic", "/security")],
       :unsorted_observation_errors}
    ]

    for {reason, errors, code} <- invalid do
      value = %{"accepted" => false, "errors" => errors}
      assert {:error, %{code: ^code}} = Observation.validate(@operation, value), reason
    end
  end

  defp error(code, phase, path), do: %{"code" => code, "phase" => phase, "path" => path}

  defp long, do: String.duplicate("a", 256)

  defp pointers(count), do: Enum.map(1..count, &"/member#{&1}")
end
