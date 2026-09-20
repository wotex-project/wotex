defmodule WotexLabWorkbench.Documentation.BrowserFixture do
  @moduledoc false

  alias DocShell.Generate.Collection
  alias Wotex.Lab.Docs.Catalogue
  alias WotexLabWorkbench.Documentation.Build

  @revision String.duplicate("a", 40)

  @spec run([String.t()]) :: :ok | no_return()
  def run(arguments) do
    {options, rest, invalid} =
      OptionParser.parse(arguments,
        strict: [
          destination: :string,
          port: :integer,
          pagefind_executable: :string,
          build_only: :boolean
        ]
      )

    if rest != [] or invalid != [], do: abort("invalid browser fixture arguments")

    destination = required_new_path(options, :destination)
    port = Keyword.get(options, :port, 4104)
    pagefind = required_file(options, :pagefind_executable)
    {:ok, catalogue} = Catalogue.load()

    {:ok, built} =
      Build.run(
        %{catalogue: catalogue, collections: collections(destination)},
        destination: destination,
        base_path: "/docs/",
        canonical_origin: "http://127.0.0.1:#{port}",
        generation_id: "documentation-browser-fixture",
        generated_at: "2026-09-21T00:00:00Z",
        pagefind_executable: pagefind
      )

    if Keyword.get(options, :build_only, false) do
      announce(port, destination, built)
      :ok
    else
      configure_endpoint(port, built)
      {:ok, _} = Application.ensure_all_started(:wotex_lab_workbench)
      announce(port, destination, built)
      Process.sleep(:infinity)
    end
  end

  defp announce(port, destination, built) do
    IO.puts(
      "WOTEX_DOCUMENTATION_FIXTURE " <>
        JSON.encode!(%{
          "origin" => "http://127.0.0.1:#{port}",
          "static" => destination,
          "cohort_digest" => built.site.cohort_digest
        })
    )
  end

  defp configure_endpoint(port, built) do
    endpoint = WotexLabWorkbenchWeb.Endpoint
    current = Application.fetch_env!(:wotex_lab_workbench, endpoint)

    Application.put_env(
      :wotex_lab_workbench,
      endpoint,
      Keyword.merge(current, http: [ip: {127, 0, 0, 1}, port: port], server: true)
    )

    Application.put_env(:wotex_lab_workbench, :documentation_site_path, built.hosted_artifact)

    Application.put_env(
      :wotex_lab_workbench,
      :documentation_search_root,
      Path.join(Path.dirname(built.hosted_artifact), "search")
    )
  end

  defp collections(destination) do
    for source <- Catalogue.source_ids() do
      id = String.replace(source, "-", "_")
      collection(id, documents(id), destination)
    end
  end

  defp collection(id, documents, destination) do
    {:ok, descriptor} =
      Collection.new(%{
        id: id,
        title: String.replace(id, "_", " "),
        version: "0.1.0",
        revision: @revision,
        tree_digest: "sha256:" <> String.duplicate("b", 64),
        artifact_dir: Path.join([Path.dirname(destination), "collections", id]),
        source_url: "https://example.test/#{id}/tree/#{@revision}",
        edit_base_url: "https://example.test/#{id}/edit/main",
        license: "Apache-2.0",
        audience: "public",
        status: "stable"
      })

    %{
      descriptor: descriptor,
      generation_id: "browser-#{id}",
      content_digest: Collection.digest(documents),
      artifacts: %{},
      sources: [],
      documents: documents
    }
  end

  defp documents("family_docs" = id) do
    [
      document(id, "readme", "guide", "Start", "docs/README.md", "Guide constellation"),
      document(
        id,
        "rtl-guide",
        "guide",
        "دليل عربي",
        "docs/guides/rtl.md",
        "Arabic compass",
        "ar"
      )
    ]
  end

  defp documents("wotex" = id) do
    [
      document(
        id,
        "Wotex.Thing",
        "module",
        "Wotex.Thing",
        "lib/wotex/thing.ex",
        "Module member orbital decoder"
      )
    ]
  end

  defp documents("wotex_ble" = id),
    do: [
      document(id, "beacon-profile", "guide", "Bluetooth beacon", "README.md", "Protocol beacon")
    ]

  defp documents("wotex_coap" = id) do
    [
      document(
        id,
        "datagram-contract",
        "guide",
        "Datagram contract",
        "docs/packages/wotex-coap/specs/WCO.01.md",
        "Specification covenant"
      )
    ]
  end

  defp documents("wotex_nx" = id) do
    [
      document(
        id,
        "tensor-notebook",
        "notebook",
        "Tensor notebook",
        "notebooks/tensor.livemd",
        "Notebook tensor"
      )
    ]
  end

  defp documents("wotex_lab" = id) do
    [
      document(
        id,
        "release-proof",
        "evidence",
        "Release proof",
        "docs/packages/wotex-lab/provenance/release.md",
        "Evidence lantern"
      )
    ]
  end

  defp documents("wotex_binding_http" = id) do
    [
      document(
        id,
        "widgets",
        "openapi",
        "Widget API",
        "openapi.json",
        "API operation widget flight"
      )
    ]
  end

  defp documents(id) do
    [document(id, "overview", "guide", "#{id} overview", "README.md", "#{id} documentation")]
  end

  defp document(id, document_id, kind, title, source_path, text, locale \\ "en") do
    %{
      "id" => "#{id}:#{document_id}",
      "collection_id" => id,
      "document_id" => document_id,
      "kind" => kind,
      "title" => title,
      "ast" => [node("h2", ["Details"]), node("p", [text])],
      "meta" => %{
        "audience" => "public",
        "locale" => locale,
        "source_path" => source_path,
        "status" => "stable"
      }
    }
  end

  defp node(tag, content),
    do: %{"tag" => tag, "attrs" => %{}, "content" => content, "meta" => %{}}

  defp required_new_path(options, key) do
    case Keyword.get(options, key) do
      path when is_binary(path) ->
        path = Path.expand(path)

        if Path.type(path) == :absolute and not File.exists?(path),
          do: path,
          else: abort("--destination must name a new absolute path")

      _ ->
        abort("--destination is required")
    end
  end

  defp required_file(options, key) do
    case Keyword.get(options, key) do
      path when is_binary(path) ->
        path = Path.expand(path)
        if File.regular?(path), do: path, else: abort("--pagefind-executable is not a file")

      _ ->
        abort("--pagefind-executable is required")
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

WotexLabWorkbench.Documentation.BrowserFixture.run(System.argv())
