defmodule WotexLabWorkbench.Documentation.Assets do
  @moduledoc "The local reader assets shared by hosted documentation and static export."

  @files [
    {"documentation.css", "text/css", "css/documentation.css"},
    {"wotex.svg", "image/svg+xml", "brand/wotex.svg"},
    {"search.svg", "image/svg+xml", "icons/search.svg"},
    {"arrow-up-right.svg", "image/svg+xml", "icons/arrow-up-right.svg"},
    {"copy.svg", "image/svg+xml", "icons/copy.svg"},
    {"menu.svg", "image/svg+xml", "icons/menu.svg"},
    {"x.svg", "image/svg+xml", "icons/x.svg"}
  ]

  @doc "Returns logical assets; DocShell owns destination paths and content hashing."
  @spec all() :: {:ok, [struct()]} | {:error, term()}
  def all do
    root = Application.app_dir(:wotex_lab_workbench, "priv/static")

    with {:ok, files} <- files(root),
         {:ok, browser} <- browser(root) do
      tokens = asset("tokens.css", "text/css", Wotex.Lab.DesignSystem.stylesheet())
      {:ok, [tokens, browser | files]}
    end
  end

  defp files(root) do
    Enum.reduce_while(@files, {:ok, []}, fn {name, media_type, path}, {:ok, assets} ->
      case File.read(Path.join(root, path)) do
        {:ok, bytes} -> {:cont, {:ok, [asset(name, media_type, bytes) | assets]}}
        {:error, reason} -> {:halt, {:error, {:documentation_asset_unavailable, name, reason}}}
      end
    end)
  end

  defp browser(root) do
    with {:ok, bytes} <- File.read(Path.join(root, ".vite/manifest.json")),
         {:ok, manifest} <- Jason.decode(bytes),
         %{"file" => path, "isEntry" => true} = entry <- manifest["assets/documentation.ts"],
         true <- Regex.match?(~r/\Aassets\/workbench-[a-zA-Z0-9_-]+\.js\z/, path),
         [] <- Map.get(entry, "imports", []),
         [] <- Map.get(entry, "dynamicImports", []),
         {:ok, browser} <- File.read(Path.join(root, path)) do
      {:ok, asset("documentation.js", "text/javascript", browser)}
    else
      _ -> {:error, :documentation_browser_asset_unavailable}
    end
  end

  defp asset(path, media_type, bytes),
    do: struct!(DocShell.Presentation.Asset, path: path, media_type: media_type, bytes: bytes)
end
