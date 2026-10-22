defmodule WotexLabWorkbench.Documentation.ApiMembersTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexLabWorkbench.Documentation.ApiMembers

  test "documented members become linked pages without duplicating prose in the module" do
    members = [member("read_property", 3), member("read_property", 2), member("hidden", 0, "")]
    original = module_document(members)
    collection = %{documents: [original], content_digest: "original collection digest"}

    assert {:ok, [projected], %{included: 2, excluded: 1}} = ApiMembers.project([collection])
    assert projected.content_digest == collection.content_digest
    assert [overview, first, second] = projected.documents
    assert first["title"] == "read_property/2"
    assert second["title"] == "read_property/3"
    assert first["meta"]["source_path"] == "packages/wotex-runtime/lib/consumed_thing.ex"
    refute Map.has_key?(first["meta"], "members")
    assert Jason.encode!(overview["ast"]) =~ "doc:" <> first["id"]
    refute Jason.encode!(overview["ast"]) =~ "Read the selected Property"
    assert Jason.encode!(first["ast"]) =~ "Read the selected Property"
    assert Jason.encode!(first["ast"]) =~ "Since: "
    assert Jason.encode!(first["ast"]) =~ "read_property(name, options)"
    assert Jason.encode!(first["ast"]) =~ "doc:" <> original["id"]

    reversed = %{collection | documents: [module_document(Enum.reverse(members))]}
    assert {:ok, [again], _} = ApiMembers.project([reversed])
    assert Enum.drop(again.documents, 1) == Enum.drop(projected.documents, 1)
  end

  test "hidden modules and hidden or absent member prose remain excluded" do
    members = [
      member("visible", 0),
      member("hidden", 0) |> Map.put("doc_state", "hidden"),
      member("none", 0, " ")
    ]

    assert {:ok, [%{documents: [_, visible]}], %{included: 1, excluded: 2}} =
             ApiMembers.project([%{documents: [module_document(members)]}])

    assert visible["title"] == "visible/0"

    hidden = put_in(module_document(members), ["meta", "moduledoc"], "hidden")

    assert {:ok, [%{documents: []}], %{included: 0, excluded: 3}} =
             ApiMembers.project([%{documents: [hidden]}])
  end

  test "all documented callable and type kinds retain separate identities" do
    members =
      for kind <- ~w(function macro callback macrocallback type opaque),
          do: Map.put(member("entry", 1), "kind", kind)

    assert {:ok, [%{documents: [_ | pages]}], %{included: 6}} =
             ApiMembers.project([%{documents: [module_document(members)]}])

    assert length(Enum.uniq_by(pages, & &1["id"])) == 6
    assert Enum.map(pages, & &1["kind"]) == ~w(function macro callback macrocallback type opaque)
  end

  test "malformed, duplicate and oversized documentation fails before publication" do
    for invalid <- [
          [Map.put(member("read", 0), "arity", -1)],
          [Map.put(member("read", 0), "signatures", [7])],
          [Map.put(member("read", 0), "kind", "script")],
          [member("read", 0), member("read", 0)],
          [member("large", 0, String.duplicate("x", 262_145))],
          List.duplicate(member("read", 0), 2_049)
        ] do
      assert {:error, {:invalid_api_members, _, _}} =
               ApiMembers.project([%{documents: [module_document(invalid)]}])
    end
  end

  test "public BEAM extraction feeds the member projection without reading source files" do
    assert {:ok, extracted} = DocShell.Generate.ExDoc.extract_module(Wotex.Lab)

    document =
      Map.merge(extracted, %{
        "id" => "wotex_lab:Wotex.Lab",
        "collection_id" => "wotex_lab",
        "document_id" => "Wotex.Lab"
      })

    assert {:ok, [%{documents: [_ | members]}], %{included: included}} =
             ApiMembers.project([%{documents: [document]}])

    assert included > 0
    assert Enum.any?(members, &(&1["meta"]["api_member"]["name"] == "child_spec"))
  end

  test "search retains the bare name and unchanged prose in the one shared corpus" do
    member = %{"module" => "Wotex.Runtime.ConsumedThing", "name" => "read_property", "arity" => 3}
    page = %{metadata: %{"api_member" => member}, content_digest: "unchanged"}

    record = %{
      page_id: "member",
      section: nil,
      text: "Original documentation.",
      title: "read_property/3"
    }

    heading = %{record | section: "Examples"}
    site = %{pages: %{"member" => page}, search: [record, heading]}
    indexed = ApiMembers.index(site)
    assert indexed.pages == site.pages
    assert [indexed_record, ^heading] = indexed.search
    assert indexed_record.title == "read_property/3"

    assert indexed_record.text == "Original documentation.\nread_property"

    large = for i <- 1..17, do: member("entry_#{i}", 0, String.duplicate("x", 250_000))

    assert {:error, {:invalid_api_members, _, :module_too_large}} =
             ApiMembers.project([%{documents: [module_document(large)]}])
  end

  defp member(
         name,
         arity,
         doc \\ "Read the selected Property.\n\n## Examples\n\n`read_property/3` returns a result."
       ) do
    %{
      "kind" => "function",
      "name" => name,
      "arity" => arity,
      "signatures" => ["read_property(name, options)"],
      "doc" => doc,
      "metadata" => %{"since" => "0.1.0"}
    }
  end

  defp module_document(members) do
    %{
      "id" => "wotex_runtime:Wotex.Runtime.ConsumedThing",
      "collection_id" => "wotex_runtime",
      "document_id" => "Wotex.Runtime.ConsumedThing",
      "title" => "Wotex.Runtime.ConsumedThing",
      "kind" => "module",
      "ast" => [],
      "meta" => %{
        "moduledoc" => "present",
        "source_path" => "packages/wotex-runtime/lib/consumed_thing.ex",
        "members" => members
      }
    }
  end
end
