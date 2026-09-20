defmodule WotexLabWorkbench.Documentation.Build do
  @moduledoc """
  Projects one validated cohort into the shared hosted/static site model.

  Output is written to a new staging directory. This module never replaces a
  published tree; the combined documentation/Storybook publication boundary
  performs that swap only after every producer and gate has succeeded.
  """

  alias Wotex.Lab.Docs.Projector
  alias WotexLabWorkbench.Documentation.{CommandEnvironment, DesignContract, SearchAdapter}

  @allowed_options ~w(destination base_path canonical_origin generation_id
                      pagefind_executable generated_at)a

  @doc "Projects and statically renders one already imported source cohort."
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%{catalogue: catalogue, collections: collections}, opts) when is_list(opts) do
    with :ok <- validate_options(opts),
         {:ok, destination} <- destination(Keyword.get(opts, :destination)),
         {:ok, site} <- project(collections, catalogue, opts),
         {:ok, manifest} <- export(site, destination, opts),
         {:ok, artifact, hosted_site} <-
           write_hosted_artifact(site, catalogue, manifest, destination) do
      {:ok,
       %{
         site: hosted_site,
         manifest: manifest,
         destination: destination,
         hosted_artifact: artifact
       }}
    end
  end

  def run(value, opts), do: {:error, {:invalid_documentation_site_build, value, opts}}

  defp validate_options(opts) do
    cond do
      not Keyword.keyword?(opts) or Keyword.keys(opts) -- @allowed_options != [] ->
        {:error, {:invalid_documentation_site_options, opts}}

      not valid_base?(Keyword.get(opts, :base_path, "/docs/")) ->
        {:error, {:invalid_documentation_site_base, Keyword.get(opts, :base_path)}}

      not valid_origin?(Keyword.get(opts, :canonical_origin)) ->
        {:error, {:invalid_documentation_site_origin, Keyword.get(opts, :canonical_origin)}}

      not optional_nonempty?(Keyword.get(opts, :generation_id)) ->
        {:error, {:invalid_documentation_generation, Keyword.get(opts, :generation_id)}}

      true ->
        :ok
    end
  end

  defp destination(path) do
    cond do
      not is_binary(path) or Path.type(path) != :absolute ->
        {:error, {:invalid_documentation_site_destination, path}}

      File.exists?(path) ->
        {:error, {:occupied_documentation_site_destination, path}}

      not File.dir?(Path.dirname(path)) ->
        {:error, {:missing_documentation_site_parent, Path.dirname(path)}}

      true ->
        canonical_destination(path)
    end
  end

  defp canonical_destination(path) do
    case System.cmd("pwd", ["-P"],
           cd: Path.dirname(path),
           env: CommandEnvironment.cleared(),
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, Path.join(String.trim(output), Path.basename(path))}
      {output, status} -> {:error, {:canonical_site_destination_failed, status, tail(output)}}
    end
  end

  defp project(collections, catalogue, opts) do
    module = DocShell.Presentation.SiteProjector

    if Code.ensure_loaded?(module) and function_exported?(module, :project, 1) do
      with {:ok, design_system} <- DesignContract.current() do
        source_options = [
          base_path: Keyword.get(opts, :base_path, "/docs/"),
          metadata: %{
            "catalogue_schema" => catalogue["schema_version"],
            "canonical_origin" => Keyword.get(opts, :canonical_origin),
            "tree_digest_algorithm" => catalogue["tree_digest_algorithm"],
            "design_system" => design_system
          }
        ]

        arguments = [
          collections: collections,
          source: Projector,
          source_options: source_options,
          profile: catalogue["profile"],
          generation_id: Keyword.get(opts, :generation_id, generation_id()),
          canonical_origin: Keyword.get(opts, :canonical_origin)
        ]

        module.project(arguments)
      end
    else
      {:error, :doc_shell_site_candidate_required}
    end
  end

  defp export(site, destination, opts) do
    exporter = DocShell.Presentation.StaticExporter
    renderer = PhoenixAssets.DocShell.StaticRenderer

    if Code.ensure_loaded?(exporter) and Code.ensure_loaded?(renderer) do
      search_options =
        []
        |> optional(:executable, Keyword.get(opts, :pagefind_executable))
        |> Keyword.put(:timeout, 120_000)

      arguments = [
        site: site,
        renderer: renderer,
        destination: destination,
        search_adapter: SearchAdapter,
        search_options: search_options,
        canonical_origin: Keyword.get(opts, :canonical_origin),
        generated_at: Keyword.get(opts, :generated_at)
      ]

      exporter.export(arguments)
    else
      {:error, :phoenix_assets_doc_shell_candidate_required}
    end
  end

  defp write_hosted_artifact(site, catalogue, manifest, destination) do
    directory = Path.join(destination, ".wotex")
    path = Path.join(directory, "site.etf")
    cohort_path = Path.join(directory, "cohort.json")
    metadata_path = Path.join(directory, "hosted-site.json")

    with :ok <- File.mkdir(directory),
         {:ok, search_contract} <- copy_hosted_search(manifest, destination, directory),
         hosted_site = put_in(site.metadata["search_contract"], search_contract),
         bytes =
           :erlang.term_to_binary(hosted_site, [
             :deterministic,
             {:compressed, 6},
             {:minor_version, 2}
           ]),
         {:ok, cohort_bytes} <- canonical(catalogue),
         :ok <- File.write(path, bytes, [:binary, :exclusive, :sync]),
         :ok <- File.write(cohort_path, cohort_bytes, [:binary, :exclusive, :sync]),
         {:ok, metadata_bytes} <-
           canonical(%{
             "schema_version" => "wotex-built-in-documentation/v1",
             "site_schema" => site.schema_version,
             "profile" => site.profile,
             "generation_id" => site.generation_id,
             "cohort_digest" => site.cohort_digest,
             "artifact" => ".wotex/site.etf",
             "artifact_digest" => digest(bytes)
           }),
         :ok <- File.write(metadata_path, metadata_bytes, [:binary, :exclusive, :sync]) do
      {:ok, path, hosted_site}
    end
  end

  defp copy_hosted_search(
         %{"base_path" => base_path, "files" => files, "search" => contract},
         destination,
         directory
       )
       when is_binary(base_path) and is_list(files) and is_map(contract) do
    with "pagefind/v1" <- contract["algorithm"],
         digests when is_map(digests) and map_size(digests) > 0 <- contract["digests"],
         {:ok, entry} <- search_entry(contract["path"], base_path, digests),
         :ok <- copy_search_files(digests, files, base_path, destination, directory) do
      {:ok,
       contract
       |> Map.put("path", hosted_search_path(entry))
       |> Map.update("records_path", nil, &hosted_records_path/1)
       |> Map.put(
         "digests",
         Map.new(digests, fn {relative, digest} -> {hosted_search_path(relative), digest} end)
       )}
    else
      nil -> {:error, :invalid_documentation_search_contract}
      "pagefind/v1" -> {:error, :invalid_documentation_search_contract}
      {:error, _} = error -> error
      _ -> {:error, :invalid_documentation_search_contract}
    end
  end

  defp copy_hosted_search(_, _, _), do: {:error, :invalid_documentation_search_manifest}

  defp search_entry(path, base_path, digests) when is_binary(path) do
    prefix = String.trim(base_path, "/")

    case Enum.find(Map.keys(digests), fn relative ->
           safe_relative?(relative) and path == "/" <> Path.join(prefix, relative)
         end) do
      nil -> {:error, :invalid_documentation_search_entry}
      entry -> {:ok, entry}
    end
  end

  defp search_entry(_, _, _), do: {:error, :invalid_documentation_search_entry}

  defp copy_search_files(digests, files, base_path, destination, directory) do
    entries = Map.new(files, &{&1["path"], &1})
    prefix = String.trim(base_path, "/")

    digests
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn {relative, expected}, :ok ->
      static = Path.join(prefix, relative)
      source = Path.join(destination, static)
      target = Path.join([directory, "search", relative])

      with true <- safe_relative?(relative) and digest?(expected),
           %{"digest" => ^expected, "size" => size} when is_integer(size) and size > 0 <-
             Map.get(entries, static),
           {:ok, %{type: :regular, size: ^size}} <- File.lstat(source),
           :ok <- File.mkdir_p(Path.dirname(target)),
           :ok <- File.cp(source, target) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, {:invalid_documentation_search_asset, relative}}}
      end
    end)
  end

  defp hosted_records_path(path) when is_binary(path) do
    if safe_relative?(path), do: hosted_search_path(path), else: nil
  end

  defp hosted_records_path(_), do: nil
  defp hosted_search_path(relative), do: "/docs-search/" <> relative

  defp safe_relative?(path) when is_binary(path) do
    path != "" and Path.type(path) == :relative and ".." not in Path.split(path) and
      not String.contains?(path, ["\\", <<0>>])
  end

  defp safe_relative?(_), do: false

  defp canonical(value) do
    module = DocShell.Json.Canonical

    if Code.ensure_loaded?(module) and function_exported?(module, :encode, 1),
      do: module.encode(value),
      else: {:error, :doc_shell_site_candidate_required}
  end

  defp valid_base?(path) when is_binary(path) do
    String.starts_with?(path, "/") and String.ends_with?(path, "/") and
      ".." not in Path.split(path) and not String.contains?(path, ["\\", <<0>>])
  end

  defp valid_base?(_), do: false
  defp valid_origin?(nil), do: true

  defp valid_origin?(origin) when is_binary(origin) do
    case URI.parse(origin) do
      %URI{scheme: scheme, host: host, query: nil, fragment: nil}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp valid_origin?(_), do: false
  defp optional_nonempty?(nil), do: true
  defp optional_nonempty?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp optional(opts, _, nil), do: opts
  defp optional(opts, key, value), do: Keyword.put(opts, key, value)

  defp generation_id do
    "wotex-docs-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  defp digest(bytes),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp digest?("sha256:" <> hex),
    do: byte_size(hex) == 64 and Regex.match?(~r/\A[0-9a-f]{64}\z/, hex)

  defp digest?(_), do: false

  defp tail(output), do: String.trim(String.slice(output, -8_192, 8_192))
end
