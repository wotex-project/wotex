defmodule Mix.Tasks.WotexLab.Docs.Build do
  @shortdoc "Builds the locked static documentation publication"

  @moduledoc """
  Builds the locked Wotex documentation cohort and its Phoenix Assets catalogue.

      mix wotex_lab.docs.build \
        --destination /absolute/output \
        --repository /absolute/wotex \
        --repository-override https://github.com/wotex-project/.github=/absolute/wotex-profile \
        --offline \
        --phoenix-assets-source /absolute/phoenix-assets \
        --base-path /wotex/docs/

  Every collection is still built in its own isolated lane. The repository
  option is only a local transport override for the exact committed revision;
  it cannot change cohort identity.
  """

  use Mix.Task

  alias Wotex.Lab.Docs.{Catalogue, CohortBuilder, CohortResolver, RepositoryOverrides}
  alias WotexLabWorkbench.Documentation.Publication

  @switches [
    destination: :string,
    base_path: :string,
    catalogue: :string,
    repository: :string,
    repository_override: :keep,
    offline: :boolean,
    phoenix_assets_source: :string,
    storybook_artifact: :string,
    canonical_origin: :string,
    pagefind_executable: :string,
    profile: :string,
    generation_id: :string,
    generated_at: :string,
    workspace: :string
  ]

  @impl Mix.Task
  def run(arguments) do
    {opts, rest, invalid} = OptionParser.parse(arguments, strict: @switches)

    if rest != [] or invalid != [],
      do: Mix.raise("invalid documentation build arguments: #{inspect(rest ++ invalid)}")

    destination = required_path(opts, :destination)
    repository = required_directory(opts, :repository)
    phoenix_assets = optional_directory(opts, :phoenix_assets_source)
    storybook_artifact = optional_directory(opts, :storybook_artifact)

    if is_nil(phoenix_assets) == is_nil(storybook_artifact),
      do: Mix.raise("select exactly one of --phoenix-assets-source and --storybook-artifact")

    catalogue_path = Path.expand(Keyword.get(opts, :catalogue, Catalogue.default_path()))
    profile = Keyword.get(opts, :profile, "release")
    workspace = workspace(opts)

    result =
      with {:ok, catalogue} <- Catalogue.load(catalogue_path),
           {:ok, overrides} <- repository_overrides(catalogue, repository, opts),
           {:ok, resolved} <-
             CohortResolver.resolve(catalogue, profile,
               repository_overrides: overrides,
               workspace: Path.join(workspace, "resolution")
             ),
           {:ok, cohort} <-
             CohortBuilder.build(resolved, Path.join(workspace, "cohort"),
               repository_overrides: overrides,
               locked: profile == "release"
             ) do
        Publication.run(
          cohort,
          publication_options(opts, destination, phoenix_assets, storybook_artifact)
        )
      end

    unless Keyword.has_key?(opts, :workspace), do: File.rm_rf(workspace)

    case result do
      {:ok, publication} ->
        Mix.shell().info(JSON.encode!(publication.manifest))

      {:error, reason} ->
        Mix.raise("documentation build failed: #{inspect(reason, limit: :infinity)}")
    end
  end

  defp publication_options(opts, destination, phoenix_assets, storybook_artifact) do
    [
      destination: destination,
      base_path: Keyword.get(opts, :base_path, "/docs/"),
      generation_id: Keyword.get(opts, :generation_id, generation_id()),
      phoenix_assets_source: phoenix_assets,
      storybook_artifact: storybook_artifact
    ]
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
    |> optional(:canonical_origin, Keyword.get(opts, :canonical_origin))
    |> optional(:generated_at, Keyword.get(opts, :generated_at))
    |> optional(:pagefind_executable, pagefind(opts, phoenix_assets))
  end

  defp repository_overrides(catalogue, repository, opts) do
    primary = "https://github.com/wotex-project/wotex=#{repository}"
    values = [primary | Keyword.get_values(opts, :repository_override)]
    RepositoryOverrides.admit(catalogue, values, Keyword.get(opts, :offline, false))
  end

  defp pagefind(opts, phoenix_assets) do
    Keyword.get(opts, :pagefind_executable) ||
      if phoenix_assets,
        do: Path.join(phoenix_assets, "npm/doc-shell/node_modules/.bin/pagefind")
  end

  defp workspace(opts) do
    case Keyword.get(opts, :workspace) do
      nil ->
        path = Path.join(System.tmp_dir!(), "wotex-documentation-build-#{token()}")
        File.mkdir!(path)
        path

      path ->
        path = Path.expand(path)

        if File.exists?(path),
          do: Mix.raise("--workspace must name a new directory: #{path}")

        File.mkdir!(path)
        path
    end
  end

  defp required_path(opts, key) do
    case Keyword.get(opts, key) do
      path when is_binary(path) and path != "" -> Path.expand(path)
      _ -> Mix.raise("--#{option_name(key)} is required")
    end
  end

  defp required_directory(opts, key) do
    path = required_path(opts, key)

    if File.dir?(path),
      do: path,
      else: Mix.raise("--#{option_name(key)} is not a directory: #{path}")
  end

  defp optional_directory(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      _ -> required_directory(opts, key)
    end
  end

  defp option_name(key), do: String.replace(Atom.to_string(key), "_", "-")
  defp optional(opts, _, nil), do: opts
  defp optional(opts, key, value), do: Keyword.put(opts, key, value)
  defp generation_id, do: "wotex-docs-" <> token()
  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
end
