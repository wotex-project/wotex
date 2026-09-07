defmodule Wotex.Directory.MergePatchTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory.{Error, MergePatch}

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
    assert {:error,
            %Error{
              code: :invalid_request,
              phase: :patch,
              path: "/",
              details: %{operation: :patch, reason: :invalid_json_value}
            }} = MergePatch.apply(%{}, ["not", "an", "object"])

    assert {:error, %Error{code: :invalid_request, details: %{reason: :invalid_json_value}}} =
             MergePatch.apply(%{}, %{atom_key: true})

    assert {:error,
            %Error{
              path: "/a/b/c",
              details: %{reason: :maximum_depth_exceeded}
            }} = MergePatch.apply(%{}, %{"a" => %{"b" => %{"c" => true}}}, max_depth: 2)

    assert {:error,
            %Error{
              path: "/a/1",
              details: %{reason: :maximum_nodes_exceeded}
            }} = MergePatch.apply(%{}, %{"a" => [1, 2, 3]}, max_nodes: 3)
  end

  test "reports the JSON Pointer of an offending nested member" do
    assert {:error, %Error{path: "/forms/0/href~1x"}} =
             MergePatch.apply(%{}, %{"forms" => [%{"href/x" => {:not, :json}}]})
  end
end
