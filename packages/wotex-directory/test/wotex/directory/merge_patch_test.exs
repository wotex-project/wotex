defmodule Wotex.Directory.MergePatchTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory.MergePatch

  test "implements recursive RFC 7396 replacement, insertion, and removal" do
    target = %{
      "title" => "Old",
      "properties" => %{
        "temperature" => %{"type" => "number", "unit" => "C"},
        "obsolete" => %{"type" => "boolean"}
      }
    }

    patch = %{
      "title" => "New",
      "properties" => %{
        "temperature" => %{"unit" => nil, "minimum" => -40},
        "obsolete" => nil
      }
    }

    assert {:ok, merged} = MergePatch.apply(target, patch)
    assert merged["title"] == "New"

    assert merged["properties"] == %{
             "temperature" => %{"type" => "number", "minimum" => -40}
           }
  end

  test "replaces a non-object target member when patching it with an object" do
    assert {:ok, %{"value" => %{"nested" => true}}} =
             MergePatch.apply(%{"value" => 1}, %{"value" => %{"nested" => true}})
  end

  test "rejects non-object roots, non-string keys, and bounded-work violations" do
    assert {:error, :invalid_json_value} = MergePatch.apply(%{}, ["not", "an", "object"])
    assert {:error, :invalid_json_value} = MergePatch.apply(%{}, %{atom_key: true})

    assert {:error, :maximum_depth_exceeded} =
             MergePatch.apply(%{}, %{"a" => %{"b" => %{"c" => true}}}, maximum_depth: 2)

    assert {:error, :maximum_nodes_exceeded} =
             MergePatch.apply(%{}, %{"a" => [1, 2, 3]}, maximum_nodes: 3)
  end
end
