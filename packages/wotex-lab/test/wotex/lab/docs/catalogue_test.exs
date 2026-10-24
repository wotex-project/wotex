defmodule Wotex.Lab.Docs.CatalogueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Docs.Catalogue

  test "the committed cohort contains every accepted source exactly once" do
    assert {:ok, catalogue} = Catalogue.load()
    assert Enum.map(catalogue["sources"], & &1["id"]) == Catalogue.source_ids()
    assert length(catalogue["sources"]) == 22

    assert Enum.frequencies_by(catalogue["sources"], & &1["kind"]) ==
             %{"mix_package" => 20, "documentation" => 2}

    assert :ok = Catalogue.validate_locked(catalogue)

    [first | rest] = catalogue["sources"]
    unlocked = %{catalogue | "sources" => [%{first | "expected_collection_digest" => nil} | rest]}

    assert {:error, {:unlocked_documentation_source, "wotex"}} =
             Catalogue.validate_locked(unlocked)
  end

  test "new package members retain their own source roots and Hex identities" do
    assert {:ok, catalogue} = Catalogue.load()

    for id <- ~w(wotex-profiles wotex-routines wotex-udp wotex-zigbee) do
      assert {:ok, source} = Catalogue.fetch(catalogue, id)
      assert source["kind"] == "mix_package"
      assert source["repository_path"] == "packages/#{id}"
      assert source["hex_package"] == String.replace(id, "-", "_")
      assert source["documentation_roots"] == ["packages/#{id}", "docs/packages/#{id}"]
      assert source["build_command"] == ["mix", "doc_shell.build", "--no-start"]
    end

    package_revisions =
      catalogue["sources"]
      |> Enum.reject(&(&1["id"] == "wotex-dot"))
      |> Enum.map(& &1["revision"])
      |> Enum.uniq()

    assert length(package_revisions) == 1
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

  test "malformed source records, revision types and credential-bearing URLs return errors" do
    assert {:ok, catalogue} = Catalogue.load()
    [first | rest] = catalogue["sources"]

    for source <- [nil, 12, "source", []] do
      assert {:error, :invalid_documentation_cohort} =
               Catalogue.validate(%{catalogue | "sources" => [source | rest]})
    end

    for revision <- [nil, 12, [], %{}] do
      invalid = %{first | "revision" => revision}

      assert {:error, {:invalid_documentation_source, "wotex"}} =
               Catalogue.validate(%{catalogue | "sources" => [invalid | rest]})
    end

    credential = %{first | "repository_url" => "https://canary@github.com/wotex-project/wotex"}

    assert {:error, {:invalid_documentation_source, "wotex"}} =
             Catalogue.validate(%{catalogue | "sources" => [credential | rest]})
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
