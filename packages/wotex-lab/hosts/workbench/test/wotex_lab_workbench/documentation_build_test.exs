defmodule WotexLabWorkbench.Documentation.BuildTest do
  use ExUnit.Case, async: false

  alias DocShell.Generate.Collection
  alias Wotex.Lab.Docs.Catalogue
  alias WotexLabWorkbench.Documentation.{Build, DesignContract}

  test "canonical origin excludes the deployment path" do
    origin = "https://wotex-project.github.io/wotex"

    assert {:error, {:invalid_documentation_site_origin, ^origin}} =
             Build.run(%{catalogue: %{}, collections: []},
               destination: temporary_path("invalid-origin"),
               canonical_origin: origin
             )
  end

  if Code.ensure_loaded?(DocShell.Presentation.SiteProjector) and
       Code.ensure_loaded?(PhoenixAssets.DocShell.StaticRenderer) do
    @tag timeout: 120_000
    test "one model renders complete root and repository-subpath static sites" do
      {:ok, catalogue} = Catalogue.load()
      pagefind = pagefind_executable()

      for base_path <- ["/docs/", "/wotex/docs/"] do
        destination = temporary_path("site")
        on_exit(fn -> File.rm_rf!(destination) end)

        assert {:ok, built} =
                 Build.run(
                   %{catalogue: catalogue, collections: collections()},
                   destination: destination,
                   base_path: base_path,
                   canonical_origin: "https://wotex.example",
                   generation_id: "documentation-build-test",
                   pagefind_executable: pagefind
                 )

        prefix = String.trim(base_path, "/")
        start = Path.join([destination, prefix, "start/index.html"])
        records = Path.join([destination, prefix, "search-records.json"])
        pagefind_entry = Path.join([destination, prefix, "pagefind/pagefind.js"])

        assert File.regular?(start)
        assert File.regular?(records)
        assert File.regular?(pagefind_entry)
        assert File.regular?(Path.join(destination, "site-manifest.json"))
        assert File.regular?(Path.join(destination, "llms.txt"))
        assert File.regular?(Path.join(destination, "llms-full.txt"))
        assert File.regular?(Path.join(destination, "sitemap.xml"))
        assert File.regular?(Path.join(destination, "robots.txt"))

        html = File.read!(start)
        assert html =~ "Portable Wotex documentation"
        assert html =~ ~s(href="#{base_path}runtime/overview/")

        assert html =~
                 ~s(href="https://github.com/wotex-project/wotex/tree/#{revision()}/docs/catalogue.yaml")

        assert html =~
                 ~s(href="https://github.com/wotex-project/wotex/tree/#{revision()}/CONTRIBUTING.md#command-reference")

        assert html =~ "hello@wotex.example"
        refute html =~ "mailto:"
        assert html =~ "data-cohort-digest=\"#{built.site.cohort_digest}\""
        assert html =~ "data-pa-doc-shell"
        refute html =~ ~r/<script[^>]+src="https?:\/\//
        refute html =~ ~r/<link[^>]+rel="stylesheet"[^>]+href="https?:\/\//
        refute html =~ "phoenix_live_view"
        refute html =~ "live/websocket"
        encoded_search = Jason.encode!(built.site.search)
        encoded_search = Base.url_encode64(encoded_search)
        refute html =~ encoded_search

        decoded_records = JSON.decode!(File.read!(records))
        assert length(decoded_records) == length(built.site.search)
        assert Enum.any?(decoded_records, &(&1["collection"] == "wotex_ble"))

        hosted = :erlang.binary_to_term(File.read!(built.hosted_artifact), [:safe])
        hosted_pagefind = Path.join(destination, ".wotex/search/pagefind/pagefind.js")
        assert File.regular?(hosted_pagefind)
        assert built.manifest["search"]["algorithm"] == "pagefind/v1"
        assert built.manifest["search"]["path"] == base_path <> "pagefind/pagefind.js"

        assert hosted.metadata["search_contract"]["path"] ==
                 "/docs-search/pagefind/pagefind.js"

        assert hosted.cohort_digest == built.site.cohort_digest
        assert hosted.routes == built.site.routes
        assert hosted.search == built.site.search
        assert built.site.redirects[base_path] == base_path <> "start/"
        assert built.manifest["base_path"] == base_path
        assert {:ok, contract} = DesignContract.current()
        assert built.site.metadata["design_system"] == contract
      end
    end
  end

  defp collections do
    for id <- Catalogue.source_ids(), do: collection(String.replace(id, "-", "_"))
  end

  defp collection(id) do
    documents = if id == "wotex", do: [document(id), module_document()], else: [document(id)]

    {:ok, descriptor} =
      Collection.new(%{
        id: id,
        title: id,
        version: "0.1.0",
        revision: revision(),
        tree_digest: "sha256:" <> String.duplicate("b", 64),
        artifact_dir: temporary_path(id),
        source_url: source_url(id),
        edit_base_url: "https://github.com/wotex-project/wotex/edit/main",
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

  defp document("family_docs" = id) do
    id
    |> guide("readme", "docs/README.md")
    |> Map.update!("ast", fn ast ->
      [
        %{
          "tag" => "p",
          "attrs" => %{},
          "content" => [
            %{
              "tag" => "a",
              "attrs" => %{"href" => "../packages/wotex-runtime/README.md"},
              "content" => ["Runtime"],
              "meta" => %{}
            },
            " and ",
            %{
              "tag" => "a",
              "attrs" => %{"href" => "catalogue.yaml"},
              "content" => ["catalogue"],
              "meta" => %{}
            },
            " or ",
            %{
              "tag" => "a",
              "attrs" => %{"href" => "mailto:hello@wotex.example"},
              "content" => ["hello@wotex.example"],
              "meta" => %{}
            },
            " or ",
            %{
              "tag" => "a",
              "attrs" => %{"href" => "../CONTRIBUTING.md#command-reference"},
              "content" => ["commands"],
              "meta" => %{}
            }
          ],
          "meta" => %{}
        }
        | ast
      ]
    end)
  end

  defp document("wotex_runtime" = id),
    do: guide(id, "overview", "packages/wotex-runtime/README.md")

  defp document("wotex_dot" = id), do: guide(id, "governance", "CONTRIBUTING.md")
  defp document(id), do: guide(id, "overview", "README.md")

  defp module_document do
    content = [node("p", ["Core Thing Description API."])]

    %{
      "id" => "wotex:Wotex.ThingDescription",
      "collection_id" => "wotex",
      "document_id" => "Wotex.ThingDescription",
      "kind" => "module",
      "title" => "Wotex.ThingDescription",
      "ast" => content,
      "meta" => %{}
    }
  end

  defp guide(id, document_id, source_path) do
    %{
      "id" => "#{id}:#{document_id}",
      "collection_id" => id,
      "document_id" => document_id,
      "kind" => "guide",
      "title" => if(id == "family_docs", do: "Portable Wotex documentation", else: id),
      "ast" => [node("p", ["Portable Wotex documentation for #{id}."])],
      "meta" => %{"source_path" => source_path}
    }
  end

  defp node(tag, content),
    do: %{"tag" => tag, "attrs" => %{}, "content" => content, "meta" => %{}}

  defp pagefind_executable do
    Mix.Project.deps_paths()
    |> Map.fetch!(:phoenix_assets)
    |> Path.join("npm/doc-shell/node_modules/.bin/pagefind")
  end

  defp temporary_path(name) do
    Path.join(System.tmp_dir!(), "wotex-doc-#{name}-#{token()}")
  end

  defp revision, do: String.duplicate("a", 40)
  defp source_url("wotex_dot"), do: "https://github.com/wotex-project/.github/tree/#{revision()}"
  defp source_url(_), do: "https://github.com/wotex-project/wotex/tree/#{revision()}"
  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
end
