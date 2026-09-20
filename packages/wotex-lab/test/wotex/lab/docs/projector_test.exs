defmodule Wotex.Lab.Docs.ProjectorTest do
  use ExUnit.Case, async: true

  alias DocShell.Generate.Collection
  alias Wotex.Lab.Docs.{Catalogue, Projector}

  test "projects the complete closed cohort into canonical routes and navigation" do
    assert {:ok, declaration} = Projector.project(collections(), base_path: "/docs/")

    assert length(declaration["pages"]) == 19
    assert page_route(declaration, "family_docs:readme") == "/start/"

    assert page_route(declaration, "wotex:Wotex.ThingDescription") ==
             "/api/wotex/wotex-thing-description/"

    assert page_route(declaration, "wotex_binding_http:overview") ==
             "/bindings/http/overview/"

    assert page_route(declaration, "wotex_ble:overview") ==
             "/protocols/bluetooth-le/overview/"

    assert page_route(declaration, "wotex_continuum:overview") ==
             "/discovery/exchange/overview/"

    assert page_route(declaration, "wotex_dot:governance") ==
             "/project/wotex-dot/governance/"

    assert declaration["redirects"]["/docs/"] == "family_docs:readme"
    assert Enum.map(declaration["navigation"], & &1["title"]) == expected_sections()
  end

  if Code.ensure_loaded?(DocShell.Presentation.SiteProjector) do
    test "candidate DocShell validates the complete projected site" do
      collections = collections()

      assert {:ok, site} =
               DocShell.Presentation.SiteProjector.project(
                 collections: collections,
                 source: Projector,
                 source_options: [base_path: "/docs/"],
                 profile: "release",
                 generation_id: "wotex-test-generation",
                 canonical_origin: "https://wotex.io"
               )

      assert map_size(site.pages) == 19
      assert site.routes["/docs/start/"] == "family_docs:readme"

      assert site.routes["/docs/api/wotex/wotex-thing-description/"] ==
               "wotex:Wotex.ThingDescription"

      assert site.routes["/docs/bindings/http/overview/"] ==
               "wotex_binding_http:overview"

      assert site.routes["/docs/protocols/bluetooth-le/overview/"] == "wotex_ble:overview"

      assert site.routes["/docs/discovery/exchange/overview/"] ==
               "wotex_continuum:overview"

      assert site.routes["/docs/project/wotex-dot/governance/"] == "wotex_dot:governance"
      assert site.redirects["/docs/"] == "/docs/start/"
      assert Enum.all?(site.pages, fn {_, page} -> page.source_revision == revision() end)
      assert Enum.all?(site.search, &String.starts_with?(&1.route, "/docs/"))
    end
  end

  test "rejects incomplete, reordered and route-colliding cohorts" do
    collections = collections()

    assert {:error, {:invalid_documentation_collection_order, _}} =
             Projector.project(Enum.drop(collections, -1), [])

    assert {:error, {:invalid_documentation_collection_order, _}} =
             Projector.project(Enum.reverse(collections), [])

    [first | rest] = collections
    [document | other_documents] = first.documents
    collision = %{document | "id" => "wotex:duplicate", "document_id" => document["document_id"]}
    first = %{first | documents: [document, collision | other_documents]}

    assert {:error, {:duplicate_documentation_route, _, _}} =
             Projector.project([first | rest], [])
  end

  test "rejects unknown projector options and unsafe base paths" do
    assert {:error, {:unknown_documentation_projector_options, [:surprise]}} =
             Projector.project(collections(), surprise: true)

    assert {:error, {:invalid_documentation_base_path, "/docs/../private/"}} =
             Projector.project(collections(), base_path: "/docs/../private/")
  end

  test "declares every admitted page locale while retaining English as the default" do
    [first | rest] = collections()
    [document | documents] = first.documents
    document = put_in(document, ["meta", "locale"], "ar")

    assert {:ok, declaration} =
             Projector.project([%{first | documents: [document | documents]} | rest], [])

    assert declaration["default_locale"] == "en"
    assert declaration["locales"] == ["en", "ar"]

    invalid = put_in(document, ["meta", "locale"], "../../private")

    assert {:error, {:invalid_documentation_locale, "../../private"}} =
             Projector.project([%{first | documents: [invalid | documents]} | rest], [])
  end

  defp collections do
    for id <- Catalogue.source_ids(), do: collection(String.replace(id, "-", "_"))
  end

  defp collection(id) do
    documents = documents(id)

    {:ok, descriptor} =
      Collection.new(%{
        id: id,
        title: id,
        version: "0.1.0",
        revision: revision(),
        tree_digest: "sha256:" <> String.duplicate("b", 64),
        artifact_dir: "/tmp/#{id}",
        source_url:
          "https://github.com/wotex-project/#{String.replace(id, "_", "-")}/blob/#{revision()}",
        edit_base_url: "https://github.com/wotex-project/#{String.replace(id, "_", "-")}/edit/main",
        license: "Apache-2.0"
      })

    %{
      descriptor: descriptor,
      generation_id: "generation-#{id}",
      content_digest: Collection.digest(documents),
      artifacts: %{},
      sources: [],
      documents: documents
    }
  end

  defp documents("wotex" = id), do: [document(id), guide(id, "overview", "README.md")]
  defp documents(id), do: [document(id)]

  defp document("family_docs" = id), do: guide(id, "readme", "docs/README.md")
  defp document("wotex_dot" = id), do: guide(id, "governance", "profile/README.md")

  defp document("wotex" = id) do
    %{
      "id" => "#{id}:Wotex.ThingDescription",
      "collection_id" => id,
      "document_id" => "Wotex.ThingDescription",
      "kind" => "module",
      "title" => "Wotex.ThingDescription",
      "ast" => [heading("Thing Description")],
      "meta" => %{"source_path" => "lib/wotex/thing_description.ex"}
    }
  end

  defp document(id), do: guide(id, "overview", "README.md")

  defp guide(id, document_id, source_path) do
    %{
      "id" => "#{id}:#{document_id}",
      "collection_id" => id,
      "document_id" => document_id,
      "kind" => "guide",
      "title" => String.replace(document_id, "-", " ") |> String.capitalize(),
      "ast" => [heading("Overview")],
      "meta" => %{"source_path" => source_path}
    }
  end

  defp heading(title) do
    %{"tag" => "h2", "attrs" => %{}, "content" => [title], "meta" => %{}}
  end

  defp page_route(declaration, id) do
    declaration["pages"]
    |> Enum.find(&(&1["id"] == id))
    |> Map.fetch!("route")
  end

  defp expected_sections do
    [
      "Start",
      "Core Thing Description",
      "Runtime",
      "Bindings",
      "Protocols",
      "Discovery and exchange",
      "Numerical computing",
      "Conformance",
      "Lab and workbench",
      "API reference",
      "Project and contribution"
    ]
  end

  defp revision, do: String.duplicate("a", 40)
end
