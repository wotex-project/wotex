defmodule WotexLabWorkbench.Documentation do
  @moduledoc """
  Loads the inert, release-built documentation site used by public routes.

  Runtime never resolves Git revisions, compiles documentation or fetches a
  source. A validated DocShell site is either supplied directly by a host test
  or read from the release's bounded safe-term artifact.
  """

  @maximum_site_bytes 256 * 1_024 * 1_024
  @maximum_search_asset_bytes 32 * 1_024 * 1_024
  @site_modules [
    DocShell.Presentation.Heading,
    DocShell.Presentation.Link,
    DocShell.Presentation.NavigationItem,
    DocShell.Presentation.Page,
    DocShell.Presentation.Renderer.CapabilityRequirement,
    DocShell.Presentation.Site,
    DocShell.Presentation.SiteSearchEntry
  ]
  @site_atoms ~w(__struct__ acceptable_states audience banner base_path breadcrumbs
                 canonical_url children cohort_digest collection collection_id content
                 content_digest default_locale description document document_id edit_url
                 essential? fallback fallback_digest feature_id generation_id headings hero id
                 kind last_modified level locale locales meta metadata navigation navigation?
                 next package_version page_id pages path previous profile redirects requirements
                 route routes schema_version search search? section source_path source_revision
                 source_url status tags template text title version)a
  @asset_paths %{
    "doc-shell.css" => "/docs-assets/doc-shell.css",
    "doc-shell-browser.js" => "/docs-assets/doc-shell-browser.js"
  }

  @doc "Returns the configured built-in site without starting any service."
  @spec site() :: {:ok, struct()} | {:error, term()}
  def site do
    case Application.get_env(:wotex_lab_workbench, :documentation_site) do
      nil -> load(site_path())
      configured -> validate(configured)
    end
  end

  @doc "Finds one canonical route or explicit redirect in the built-in site."
  @spec fetch_route(String.t()) ::
          {:ok, struct(), struct(), map()} | {:redirect, String.t()} | {:error, term()}
  def fetch_route(route) when is_binary(route) and byte_size(route) <= 2_048 do
    with {:ok, site} <- site() do
      case site.redirects do
        %{^route => target} ->
          {:redirect, target}

        _ ->
          with {:ok, page_id} <- Map.fetch(site.routes, route),
               {:ok, page} <- Map.fetch(site.pages, page_id) do
            {:ok, site, page, context(site, page)}
          else
            :error -> {:error, :documentation_not_found}
          end
      end
    end
  end

  def fetch_route(_), do: {:error, :documentation_not_found}

  @doc "Returns one local Phoenix Assets documentation asset."
  @spec asset(String.t()) :: {:ok, String.t(), binary(), String.t()} | {:error, term()}
  def asset(name) when is_map_key(@asset_paths, name) do
    module = PhoenixAssets.DocShell.Assets

    if Code.ensure_loaded?(module) and function_exported?(module, :all, 0) do
      case Enum.find(:erlang.apply(module, :all, []), &(&1.path == name)) do
        %{media_type: media_type, bytes: bytes} ->
          {:ok, media_type, bytes, digest(bytes)}

        _ ->
          {:error, :documentation_asset_unavailable}
      end
    else
      {:error, :documentation_renderer_unavailable}
    end
  end

  def asset(_), do: {:error, :documentation_asset_not_found}

  @doc "Returns one release-built Pagefind asset from the admitted local search tree."
  @spec search_asset([String.t()]) ::
          {:ok, String.t(), binary(), String.t()} | {:error, term()}
  def search_asset(segments) when is_list(segments) and segments != [] do
    with true <- Enum.all?(segments, &safe_segment?/1),
         root = search_root(),
         path = Path.join([root | segments]),
         true <- String.starts_with?(Path.expand(path), Path.expand(root) <> "/"),
         :ok <- regular_path(root, segments),
         {:ok, %{size: size}} when size <= @maximum_search_asset_bytes <- File.stat(path),
         {:ok, bytes} <- File.read(path) do
      {:ok, search_media_type(path), bytes, digest(bytes)}
    else
      _ -> {:error, :documentation_search_asset_not_found}
    end
  end

  def search_asset(_), do: {:error, :documentation_search_asset_not_found}

  @doc "Returns the stable hosted paths for the shared renderer assets."
  @spec asset_paths() :: %{String.t() => String.t()}
  def asset_paths, do: @asset_paths

  defp context(site, page) do
    %{
      site_title: site.title,
      cohort_digest: site.cohort_digest,
      base_path: site.base_path,
      current_route: page.route,
      locale: page.locale,
      navigation: site.navigation,
      search: %{
        "contract" => Map.get(site.metadata, "search_contract", %{"algorithm" => "embedded/v1"}),
        "records" => site.search
      },
      design_system: Map.get(site.metadata, "design_system", %{}),
      assets: @asset_paths,
      canonical_origin: Map.get(site.metadata, "canonical_origin")
    }
  end

  defp load(path) do
    with {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size <= @maximum_site_bytes,
         {:ok, bytes} <- File.read(path),
         {:ok, site} <- decode(bytes) do
      validate(site)
    else
      false -> {:error, :invalid_documentation_site_artifact}
      {:error, reason} -> {:error, {:documentation_site_unavailable, reason}}
    end
  end

  defp decode(bytes) do
    if Enum.all?(@site_modules, &match?({:module, _}, Code.ensure_loaded(&1))) and
         Enum.all?(@site_atoms, &is_atom/1) do
      {:ok, :erlang.binary_to_term(bytes, [:safe])}
    else
      {:error, :documentation_renderer_unavailable}
    end
  rescue
    ArgumentError -> {:error, :invalid_documentation_site_artifact}
  end

  defp validate(%{__struct__: module} = site) do
    expected = DocShell.Presentation.Site

    if Code.ensure_loaded?(expected) and module == expected and
         site.schema_version == "doc-shell-site/v1" and digest?(site.cohort_digest) and
         is_map(site.pages) and map_size(site.pages) > 0 and is_map(site.routes) and
         is_map(site.redirects) and is_list(site.navigation) and is_list(site.search) do
      {:ok, site}
    else
      {:error, :invalid_documentation_site}
    end
  end

  defp validate(_), do: {:error, :invalid_documentation_site}

  defp site_path do
    Application.get_env(
      :wotex_lab_workbench,
      :documentation_site_path,
      Application.app_dir(:wotex_lab_workbench, "priv/documentation/site.etf")
    )
  end

  defp search_root do
    Application.get_env(
      :wotex_lab_workbench,
      :documentation_search_root,
      Path.join(Path.dirname(site_path()), "search")
    )
  end

  defp regular_path(root, segments) do
    segments
    |> Enum.scan(root, &Path.join(&2, &1))
    |> Enum.reduce_while(:ok, fn path, :ok ->
      case File.lstat(path) do
        {:ok, %{type: type}} when type in [:directory, :regular] -> {:cont, :ok}
        _ -> {:halt, {:error, :unsafe_documentation_search_path}}
      end
    end)
  end

  defp safe_segment?(segment) when is_binary(segment) do
    segment not in ["", ".", ".."] and
      Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/, segment)
  end

  defp safe_segment?(_), do: false

  defp search_media_type(path) do
    basename = Path.basename(path)

    cond do
      String.ends_with?(basename, ".js") -> "text/javascript"
      String.ends_with?(basename, ".css") -> "text/css"
      String.ends_with?(basename, ".json") -> "application/json"
      String.starts_with?(basename, "wasm.") -> "application/wasm"
      true -> "application/octet-stream"
    end
  end

  defp digest(bytes),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp digest?("sha256:" <> hex),
    do: byte_size(hex) == 64 and Regex.match?(~r/\A[0-9a-f]{64}\z/, hex)

  defp digest?(_), do: false
end
