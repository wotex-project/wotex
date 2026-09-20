defmodule Wotex.Lab.Docs.Projector do
  @moduledoc """
  Projects the closed Wotex documentation cohort into its public taxonomy.

  The projector owns only Wotex routes, labels and navigation. DocShell owns
  page construction, source provenance, anchors, link resolution, search and
  renderer-neutral validation.
  """

  if Code.ensure_loaded?(DocShell.Presentation.SiteSource) do
    @behaviour DocShell.Presentation.SiteSource
  end

  alias Wotex.Lab.Docs.Catalogue

  @collection_ids Enum.map(Catalogue.source_ids(), &String.replace(&1, "-", "_"))
  @option_keys ~w(base_path title metadata)a

  @sections [
    {"start", "Start"},
    {"concepts", "Concepts"},
    {"core", "Core Thing Description"},
    {"runtime", "Runtime"},
    {"bindings", "Bindings"},
    {"protocols", "Protocols"},
    {"discovery", "Discovery and exchange"},
    {"numerical", "Numerical computing"},
    {"conformance", "Conformance"},
    {"lab", "Lab and workbench"},
    {"api", "API reference"},
    {"specifications", "Specifications and evidence"},
    {"project", "Project and contribution"}
  ]

  @binding_names %{
    "wotex_binding_http" => "http",
    "wotex_binding_mqtt" => "mqtt"
  }

  @protocol_names %{
    "wotex_modbus" => "modbus",
    "wotex_coap" => "coap",
    "wotex_bacnet" => "bacnet",
    "wotex_opcua" => "opc-ua",
    "wotex_ble" => "bluetooth-le",
    "wotex_matter" => "matter",
    "wotex_thread" => "thread"
  }

  @doc "Returns the Wotex site declaration for the exact admitted collection cohort."
  @spec project([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def project(collections, opts) when is_list(collections) and is_list(opts) do
    with :ok <- validate_options(opts),
         :ok <- validate_cohort(collections),
         {:ok, locales} <- locales(collections),
         {:ok, pages} <- pages(collections),
         {:ok, navigation} <- navigation(pages) do
      {:ok,
       %{
         "title" => Keyword.get(opts, :title, "Wotex documentation"),
         "base_path" => Keyword.get(opts, :base_path, "/docs/"),
         "default_locale" => "en",
         "locales" => locales,
         "pages" => Enum.map(pages, & &1.declaration),
         "navigation" => navigation,
         "redirects" => redirects(pages, Keyword.get(opts, :base_path, "/docs/")),
         "metadata" =>
           Map.merge(
             %{
               "source_cohort" => "wotex-documentation-cohort/v1",
               "taxonomy" => "wotex-documentation-taxonomy/v1"
             },
             Keyword.get(opts, :metadata, %{})
           )
       }}
    end
  end

  def project(collections, opts),
    do: {:error, {:invalid_documentation_projection, collections, opts}}

  defp validate_options(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, {:invalid_documentation_projector_options, opts}}

      Keyword.keys(opts) -- @option_keys != [] ->
        {:error, {:unknown_documentation_projector_options, Keyword.keys(opts) -- @option_keys}}

      not valid_base_path?(Keyword.get(opts, :base_path, "/docs/")) ->
        {:error, {:invalid_documentation_base_path, Keyword.get(opts, :base_path)}}

      not nonempty?(Keyword.get(opts, :title, "Wotex documentation")) ->
        {:error, {:invalid_documentation_title, Keyword.get(opts, :title)}}

      not is_map(Keyword.get(opts, :metadata, %{})) ->
        {:error, {:invalid_documentation_metadata, Keyword.get(opts, :metadata)}}

      true ->
        :ok
    end
  end

  defp validate_cohort(collections) do
    ids = Enum.map(collections, &collection_id/1)

    cond do
      ids != @collection_ids ->
        {:error, {:invalid_documentation_collection_order, ids}}

      Enum.any?(collections, &(not valid_collection?(&1))) ->
        {:error, :invalid_documentation_collection}

      true ->
        :ok
    end
  end

  defp valid_collection?(%{descriptor: %{id: id}, documents: documents}) do
    id in @collection_ids and is_list(documents) and documents != [] and
      Enum.all?(documents, fn document ->
        is_map(document) and String.starts_with?(document["id"] || "", id <> ":") and
          document["collection_id"] == id and nonempty?(document["document_id"]) and
          nonempty?(document["kind"]) and nonempty?(document["title"])
      end)
  end

  defp valid_collection?(_), do: false

  defp collection_id(%{descriptor: %{id: id}}), do: id
  defp collection_id(_), do: nil

  defp locales(collections) do
    declared =
      collections
      |> Enum.flat_map(& &1.documents)
      |> Enum.map(&get_in(&1, ["meta", "locale"]))
      |> Enum.reject(&is_nil/1)

    if Enum.all?(declared, &valid_locale?/1) do
      locales =
        declared
        |> Enum.uniq()
        |> Enum.sort()
        |> List.delete("en")

      {:ok, ["en" | locales]}
    else
      {:error, {:invalid_documentation_locale, Enum.find(declared, &(not valid_locale?(&1)))}}
    end
  end

  defp valid_locale?(locale) when is_binary(locale),
    do: Regex.match?(~r/\A[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\z/, locale)

  defp valid_locale?(_), do: false

  defp pages(collections) do
    collections
    |> Enum.flat_map(fn collection ->
      Enum.map(collection.documents, &page(collection.descriptor.id, &1))
    end)
    |> reject_route_collisions()
  end

  defp page(collection_id, document) do
    section = section(collection_id, document)
    route = route(section, collection_id, document)

    %{
      id: document["id"],
      section: section,
      route: route,
      declaration: %{
        "id" => document["id"],
        "route" => route,
        "tags" => tags(section, collection_id, document),
        "metadata" => %{
          "source" => source_id(collection_id),
          "section" => section,
          "document_kind" => document["kind"]
        }
      }
    }
  end

  defp reject_route_collisions(pages) do
    case Enum.group_by(pages, & &1.route)
         |> Enum.find(fn {_, entries} -> length(entries) > 1 end) do
      nil ->
        {:ok, pages}

      {route, entries} ->
        {:error, {:duplicate_documentation_route, route, Enum.map(entries, & &1.id)}}
    end
  end

  defp section(_, %{"kind" => kind}) when kind in ["module", "openapi"], do: "api"

  defp section(collection_id, document) do
    provenance_section(document) || collection_section(collection_id, document)
  end

  defp provenance_section(%{"meta" => %{"source_path" => path}}) when is_binary(path) do
    cond do
      path_segment?(path, "specs") -> "specifications"
      path_segment?(path, "evidence") -> "specifications"
      path_segment?(path, "provenance") -> "specifications"
      true -> nil
    end
  end

  defp provenance_section(_), do: nil

  defp collection_section("family_docs", document), do: family_section(document)
  defp collection_section("wotex_dot", _), do: "project"
  defp collection_section("wotex", _), do: "core"
  defp collection_section("wotex_runtime", _), do: "runtime"
  defp collection_section(id, _) when is_map_key(@binding_names, id), do: "bindings"
  defp collection_section(id, _) when is_map_key(@protocol_names, id), do: "protocols"

  defp collection_section(id, _) when id in ["wotex_directory", "wotex_continuum"],
    do: "discovery"

  defp collection_section("wotex_nx", _), do: "numerical"
  defp collection_section("wotex_conformance", _), do: "conformance"
  defp collection_section("wotex_lab", _), do: "lab"
  defp collection_section(_, _), do: "concepts"

  defp family_section(document) do
    path = get_in(document, ["meta", "source_path"]) || ""

    cond do
      path in ["README.md", "docs/README.md"] -> "start"
      String.starts_with?(path, "docs/guides/") -> "start"
      String.starts_with?(path, "docs/architecture/") -> "concepts"
      true -> "project"
    end
  end

  defp route("start", _, %{"meta" => %{"source_path" => path}})
       when path in ["README.md", "docs/README.md"],
       do: "/start/"

  defp route("api", collection_id, document) do
    "/api/#{source_id(collection_id)}/#{slug(document["document_id"])}/"
  end

  defp route("specifications", collection_id, document) do
    kind = if evidence?(document), do: "evidence", else: "specifications"
    "/#{kind}/#{source_id(collection_id)}/#{slug(document["document_id"])}/"
  end

  defp route("bindings", collection_id, document) do
    "/bindings/#{Map.fetch!(@binding_names, collection_id)}/#{slug(document["document_id"])}/"
  end

  defp route("protocols", collection_id, document) do
    "/protocols/#{Map.fetch!(@protocol_names, collection_id)}/#{slug(document["document_id"])}/"
  end

  defp route("discovery", "wotex_directory", document),
    do: "/discovery/directory/#{slug(document["document_id"])}/"

  defp route("discovery", "wotex_continuum", document),
    do: "/discovery/exchange/#{slug(document["document_id"])}/"

  defp route("project", collection_id, document),
    do: "/project/#{source_id(collection_id)}/#{slug(document["document_id"])}/"

  defp route(section, _, document), do: "/#{section}/#{slug(document["document_id"])}/"

  defp navigation(pages) do
    grouped = Enum.group_by(pages, & &1.section)

    items =
      Enum.flat_map(@sections, fn {id, title} ->
        case Map.get(grouped, id, []) do
          [] -> []
          pages -> navigation_section(id, title, pages)
        end
      end)

    if navigation_ids(items) |> Enum.sort() == Enum.map(pages, & &1.id) |> Enum.sort(),
      do: {:ok, items},
      else: {:error, :incomplete_documentation_navigation}
  end

  defp navigation_section("start", _, [%{id: id, route: "/start/"} | rest]) do
    [
      %{"id" => id, "title" => "Start"}
      | grouped_navigation("start-more", "More ways to start", rest)
    ]
  end

  defp navigation_section(id, title, pages), do: grouped_navigation(id, title, pages)

  defp grouped_navigation(_, _, []), do: []

  defp grouped_navigation(id, title, pages) do
    sorted = Enum.sort_by(pages, &{&1.route, &1.id})

    [
      %{
        "id" => "section-#{id}",
        "title" => title,
        "children" => Enum.map(sorted, &%{"id" => &1.id})
      }
    ]
  end

  defp navigation_ids(items) do
    Enum.flat_map(items, fn
      %{"children" => children} -> navigation_ids(children)
      %{"id" => id} -> [id]
    end)
  end

  defp redirects(pages, base_path) do
    case Enum.find(pages, &(&1.route == "/start/")) do
      nil -> %{}
      page -> %{base_path => page.id}
    end
  end

  defp tags(section, collection_id, document) do
    [section, source_id(collection_id), document["kind"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp evidence?(document) do
    path = get_in(document, ["meta", "source_path"]) || ""
    path_segment?(path, "evidence") or path_segment?(path, "provenance")
  end

  defp path_segment?(path, segment), do: segment in Path.split(path)
  defp source_id(collection_id), do: String.replace(collection_id, "_", "-")

  defp slug(value) do
    slug =
      value
      |> String.normalize(:nfd)
      |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1-\\2")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    if slug == "", do: "index", else: slug
  end

  defp valid_base_path?(path) when is_binary(path) do
    String.starts_with?(path, "/") and String.ends_with?(path, "/") and
      ".." not in Path.split(path) and not String.contains?(path, ["\\", <<0>>])
  end

  defp valid_base_path?(_), do: false
  defp nonempty?(value), do: is_binary(value) and value != "" and String.valid?(value)
end
