defmodule Wotex.Profiles.ShapeTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Error, Shape}

  @suite Path.expand("../support/draft7", __DIR__)

  test "pinned independent draft-07 cells retain their expected outcomes" do
    manifest = Jason.decode!(File.read!(Path.join(@suite, "manifest.json")))

    for entry <- manifest["files"],
        Map.has_key?(entry, "selected_groups"),
        group_index <- entry["selected_groups"],
        group =
          Enum.at(
            Jason.decode!(File.read!(Path.join(@suite, Path.basename(entry["path"])))),
            group_index
          ),
        probe_index <- entry["selected_cases"][Integer.to_string(group_index)],
        probe = Enum.at(group["tests"], probe_index) do
      file = entry["path"]
      assert {:ok, errors, _, _} = Shape.check(probe["data"], group["schema"], 1_000_000, 256)

      assert errors == [] == probe["valid"],
             Path.basename(file) <> ": " <> group["description"] <> ": " <> probe["description"]
    end
  end

  test "step accounting includes failed alternatives and stops on exact exhaustion" do
    schema = %{"anyOf" => [%{"type" => "integer"}, %{"type" => "string"}]}
    assert {:ok, [], 6, false} = Shape.check(1, schema, 6, 1)
    assert {:error, %Error{code: :input_limit}} = Shape.check(1, schema, 5, 1)

    assert {:ok, [], 5, false} =
             Shape.check(
               1,
               %{"definitions" => %{"x" => %{"type" => "integer"}}, "$ref" => "#/definitions/x"},
               5,
               1
             )
  end

  test "unknown candidate keys report the installed parent and diagnostic retention is bounded" do
    schema = %{"type" => "object", "additionalProperties" => false}

    assert {:ok, errors, _, true} =
             Shape.check(%{"secret-one" => 1, "secret-two" => 2}, schema, 100, 1)

    assert errors == [%{"code" => "invalid_input", "path" => ""}]
  end
end
