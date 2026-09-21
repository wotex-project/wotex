defmodule WotexLabStorybookWeb.AssetController do
  @moduledoc false

  use WotexLabStorybookWeb, :controller

  @manifest_entry "assets/storybook.ts"
  @max_asset_bytes 4 * 1_024 * 1_024

  @spec loader(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def loader(conn, _) do
    path =
      Application.app_dir(:wotex_lab_storybook, "priv/static/contract-assets/storybook-loader.js")

    with {:ok, %File.Stat{type: :regular, size: size}} when size <= @max_asset_bytes <-
           File.lstat(path),
         {:ok, body} <- File.read(path) do
      respond(conn, "text/javascript; charset=utf-8", body)
    else
      _ -> unavailable(conn)
    end
  end

  @spec javascript(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def javascript(conn, _) do
    case manifest_entry() do
      {:ok, _, entry} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> redirect(to: "/" <> entry["file"])

      _ ->
        unavailable(conn)
    end
  end

  @spec stylesheet(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def stylesheet(conn, _) do
    with {:ok, manifest, entry} <- manifest_entry(),
         {:ok, stylesheets} <- stylesheet_paths(manifest, entry),
         {:ok, bodies} <- read_assets(stylesheets) do
      body = Enum.join(bodies, "\n") <> "\n" <> Wotex.Lab.DesignSystem.stylesheet()
      respond(conn, "text/css; charset=utf-8", body)
    else
      _ -> unavailable(conn)
    end
  end

  @spec asset(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def asset(conn, %{"path" => path}) when is_list(path) do
    with true <- path != [],
         true <- Enum.all?(path, &safe_segment?/1),
         relative = Path.join(["assets" | path]),
         {:ok, body} <- read_asset(relative) do
      content_type = MIME.from_path(relative)

      conn
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> respond(content_type, body)
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  defp manifest_entry do
    with {:ok, body} <- read_asset(".vite/manifest.json"),
         {:ok, manifest} <- Jason.decode(body),
         %{} = entry <- Map.get(manifest, @manifest_entry),
         true <- is_binary(entry["file"]) do
      {:ok, manifest, entry}
    else
      _ -> {:error, :invalid_manifest}
    end
  end

  defp stylesheet_paths(manifest, entry) do
    paths = collect_stylesheets(manifest, entry, MapSet.new(), MapSet.new())
    paths = Enum.sort(MapSet.to_list(paths))

    if paths != [],
      do: {:ok, paths},
      else: {:error, :missing_stylesheet}
  end

  defp collect_stylesheets(manifest, entry, visited, stylesheets) do
    key = entry["file"]

    if MapSet.member?(visited, key) do
      stylesheets
    else
      visited = MapSet.put(visited, key)

      stylesheets =
        Enum.reduce(entry["css"] || [], stylesheets, fn path, paths ->
          if is_binary(path), do: MapSet.put(paths, path), else: paths
        end)

      Enum.reduce(entry["imports"] || [], stylesheets, fn import, paths ->
        case manifest[import] do
          %{} = imported -> collect_stylesheets(manifest, imported, visited, paths)
          _ -> paths
        end
      end)
    end
  end

  defp read_assets(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, bodies} ->
      case read_asset(path) do
        {:ok, body} -> {:cont, {:ok, [body | bodies]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, bodies} -> {:ok, Enum.reverse(bodies)}
      error -> error
    end)
  end

  defp read_asset(relative) when is_binary(relative) do
    root = Application.fetch_env!(:wotex_lab_storybook, :workbench_static)
    target = Path.expand(relative, root)
    root_prefix = Path.expand(root) <> "/"

    with true <- String.starts_with?(target, root_prefix),
         {:ok, %File.Stat{type: :regular, size: size}} when size <= @max_asset_bytes <-
           File.lstat(target),
         {:ok, body} <- File.read(target) do
      {:ok, body}
    else
      _ -> {:error, :invalid_asset}
    end
  end

  defp safe_segment?(segment) when is_binary(segment),
    do: segment not in ["", ".", ".."] and not String.contains?(segment, ["/", "\\", <<0>>])

  defp safe_segment?(_), do: false

  defp respond(conn, content_type, body) do
    digest = Base.encode16(:crypto.hash(:sha256, body), case: :lower)
    etag = ~s("sha256-#{digest}")

    if get_req_header(conn, "if-none-match") == [etag] do
      send_resp(conn, :not_modified, "")
    else
      conn =
        if get_resp_header(conn, "cache-control") == [],
          do: put_resp_header(conn, "cache-control", "no-cache"),
          else: conn

      conn
      |> put_resp_content_type(content_type)
      |> put_resp_header("etag", etag)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(:ok, body)
    end
  end

  defp unavailable(conn) do
    conn
    |> put_resp_header("retry-after", "0")
    |> send_resp(
      :service_unavailable,
      "Build the Workbench asset graph before starting Storybook"
    )
  end
end
