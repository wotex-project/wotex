defmodule Wotex.Lab.Docs.CatalogueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Docs.Catalogue

  test "the committed cohort contains every accepted source exactly once" do
    assert {:ok, catalogue} = Catalogue.load()
    assert Enum.map(catalogue["sources"], & &1["id"]) == Catalogue.source_ids()
    assert length(catalogue["sources"]) == 18
    assert :ok = Catalogue.validate_locked(catalogue)

    [first | rest] = catalogue["sources"]
    unlocked = %{catalogue | "sources" => [%{first | "expected_collection_digest" => nil} | rest]}

    assert {:error, {:unlocked_documentation_source, "wotex"}} =
             Catalogue.validate_locked(unlocked)
  end

  test "unknown, discovered and local-task sources cannot enter the cohort" do
    {:ok, catalogue} = Catalogue.load()
    [first | rest] = catalogue["sources"]

    assert {:error, :invalid_documentation_cohort} =
             Catalogue.validate(%{catalogue | "sources" => rest})

    discovered = %{first | "id" => "wotex-unlisted", "hex_package" => "wotex_unlisted"}

    assert {:error, :invalid_documentation_cohort} =
             Catalogue.validate(%{catalogue | "sources" => [discovered | rest]})

    local = %{first | "documentation_roots" => ["docs/tasks/local/private"]}

    assert {:error, {:invalid_documentation_source, "wotex"}} =
             Catalogue.validate(%{catalogue | "sources" => [local | rest]})
  end

  test "unknown keys, source paths and mutable revisions fail closed" do
    {:ok, catalogue} = Catalogue.load()
    [first | rest] = catalogue["sources"]

    assert {:error, {:invalid_documentation_keys, :catalogue, ["caller"], []}} =
             Catalogue.validate(Map.put(catalogue, "caller", true))

    escaped = %{first | "repository_path" => "../wotex"}

    assert {:error, {:invalid_documentation_source, "wotex"}} =
             Catalogue.validate(%{catalogue | "sources" => [escaped | rest]})

    branch = %{first | "revision" => "main"}

    assert {:error, {:invalid_documentation_source, "wotex"}} =
             Catalogue.validate(%{catalogue | "sources" => [branch | rest]})
  end
end
