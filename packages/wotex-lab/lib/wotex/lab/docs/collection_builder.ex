defmodule Wotex.Lab.Docs.CollectionBuilder do
  @moduledoc """
  Builds and validates one DocShell collection in an isolated source lane.

  Mix packages compile in their own checkout, dependency directory, build
  directory and BEAM instance. Documentation-only sources use the committed
  minimal collector project in a separate checkout. The central process imports
  only the finished portable collection.
  """

  alias Wotex.Lab.Docs.{Checkout, CommandEnvironment, Staging}

  @allowed_options [:repository, :collector, :collector_repository]
  @source_root ".doc_shell_source/root"

  @typedoc "A validated collection and the lane that produced it."
  @type built :: %{
          source: map(),
          collection: map(),
          artifact_dir: Path.t(),
          admitted_files: [Path.t()],
          checkout: Path.t()
        }

  @doc "Builds one catalogue source below a new absolute lane directory."
  @spec build(map(), Path.t(), keyword()) :: {:ok, built()} | {:error, term()}
  def build(source, lane, opts \\ []) do
    with :ok <- validate_options(opts),
         :ok <- validate_lane(lane),
         {:ok, lane} <- canonical_lane(lane),
         :ok <- File.mkdir(lane),
         {:ok, checkout} <- checkout(source, lane, opts),
         {:ok, context} <- context(source, checkout, lane, opts),
         :ok <- open_staging_parent(context.staging_root),
         {:ok, staged} <- Staging.prepare(checkout, source, context.staging_root),
         :ok <- run_build(source, context),
         :ok <- remove_staging(context.staging_root),
         :ok <- clean_checkout(checkout),
         :ok <- clean_collector(context.collector_checkout, checkout),
         {:ok, collection} <- load_collection(source, context.public_dir),
         :ok <- complete_admission(staged.files, collection.sources),
         :ok <- expected_digest(source, collection.content_digest) do
      {:ok,
       %{
         source: source,
         collection: collection,
         artifact_dir: context.public_dir,
         admitted_files: staged.files,
         checkout: checkout
       }}
    end
  end

  defp validate_options(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- @allowed_options == [],
      do: :ok,
      else: {:error, {:invalid_collection_builder_options, opts}}
  end

  defp validate_lane(lane) do
    cond do
      not is_binary(lane) or Path.type(lane) != :absolute ->
        {:error, {:invalid_collection_lane, lane}}

      File.exists?(lane) ->
        {:error, {:occupied_collection_lane, lane}}

      true ->
        :ok
    end
  end

  defp canonical_lane(lane) do
    parent = Path.dirname(lane)

    case System.cmd("pwd", ["-P"],
           cd: parent,
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {output, 0} -> {:ok, Path.join(String.trim(output), Path.basename(lane))}
      {output, status} -> {:error, {:canonical_lane_failed, status, tail(output)}}
    end
  end

  defp checkout(source, lane, opts) do
    destination = Path.join(lane, "source")
    repository = Keyword.get(opts, :repository)
    checkout_opts = if repository, do: [repository: repository], else: []
    Checkout.open(source, destination, checkout_opts)
  end

  defp context(%{"kind" => "mix_package"} = source, checkout, lane, _) do
    workdir = Path.join(checkout, source["repository_path"])

    if File.regular?(Path.join(workdir, "mix.exs")) do
      {:ok, build_context(workdir, checkout, lane)}
    else
      {:error, {:missing_source_mix_project, source["id"]}}
    end
  end

  defp context(%{"kind" => "documentation"} = source, checkout, lane, opts) do
    with {:ok, collector} <- collector_source(Keyword.get(opts, :collector)),
         {:ok, collector_checkout} <-
           collector_checkout(source, collector, checkout, lane, opts),
         workdir = Path.join(collector_checkout, "tooling/doc_shell_collector"),
         true <- File.regular?(Path.join(workdir, "mix.exs")),
         true <- File.regular?(Path.join(workdir, "bin/build.exs")) do
      {:ok, build_context(workdir, collector_checkout, lane)}
    else
      false -> {:error, :missing_documentation_collector}
      {:error, _} = error -> error
    end
  end

  defp context(source, _, _, _), do: {:error, {:invalid_documentation_kind, source["kind"]}}

  defp build_context(workdir, collector_checkout, lane) do
    artifacts = Path.join(lane, "artifacts")

    %{
      workdir: workdir,
      collector_checkout: collector_checkout,
      staging_root: Path.join(workdir, @source_root),
      public_dir: Path.join(artifacts, "public"),
      private_dir: Path.join(artifacts, "private"),
      deps_dir: Path.join(lane, "deps"),
      build_dir: Path.join(lane, "build")
    }
  end

  defp collector_source(%{"repository_url" => _, "revision" => _} = collector),
    do: {:ok, collector}

  defp collector_source(value), do: {:error, {:invalid_documentation_collector, value}}

  defp collector_checkout(source, collector, source_checkout, lane, opts) do
    source_head = head(source_checkout)

    if source["repository_url"] == collector["repository_url"] and
         source_head == {:ok, collector["revision"]} do
      {:ok, source_checkout}
    else
      destination = Path.join(lane, "collector")
      repository = Keyword.get(opts, :collector_repository)
      checkout_opts = if repository, do: [repository: repository], else: []
      Checkout.open(collector, destination, checkout_opts)
    end
  end

  defp run_build(source, context) do
    env = environment(source, context)

    case run(["mix", "deps.get", "--only", "docs"], context.workdir, env, :deps) do
      :ok -> run(source["build_command"], context.workdir, env, :collection)
      {:error, _} = error -> error
    end
  end

  defp environment(source, context) do
    [
      {"MIX_ENV", "docs"},
      {"MIX_BUILD_PATH", context.build_dir},
      {"MIX_DEPS_PATH", context.deps_dir},
      {"WOTEX_PATH_DEPS", if(source["kind"] == "mix_package", do: "1", else: nil)},
      {"WOTEX_DOC_SHELL_BUILD", "1"},
      {"WOTEX_DOC_SHELL_SOURCE_ID", source["id"]},
      {"WOTEX_DOC_SHELL_TITLE", source["title"]},
      {"WOTEX_DOC_SHELL_VERSION", source["version"]},
      {"WOTEX_DOC_SHELL_REPOSITORY_PATH", source["repository_path"]},
      {"WOTEX_DOC_SHELL_SOURCE_ROOT", @source_root},
      {"WOTEX_DOC_SHELL_GUIDE_BASES", JSON.encode!([@source_root])},
      {"WOTEX_DOC_SHELL_PUBLIC_DIR", context.public_dir},
      {"WOTEX_DOC_SHELL_PRIVATE_DIR", context.private_dir},
      {"WOTEX_DOC_SHELL_REVISION", source["revision"]},
      {"WOTEX_DOC_SHELL_TREE_DIGEST", source["tree_digest"]},
      {"WOTEX_DOC_SHELL_REPOSITORY_URL", source["repository_url"]},
      {"WOTEX_DOC_SHELL_EDIT_BRANCH", source["default_branch"]},
      {"WOTEX_DOC_SHELL_LICENSE", source["license"]},
      {"DOC_SHELL_CANDIDATE", nil},
      {"PHOENIX_ASSETS_CANDIDATE", nil}
    ]
  end

  defp run([executable | args], workdir, env, phase)
       when is_binary(executable) and is_list(args) do
    case System.cmd(executable, args,
           cd: workdir,
           env: CommandEnvironment.scrubbed(env),
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {_, 0} -> :ok
      {output, status} -> {:error, {:documentation_command_failed, phase, status, tail(output)}}
    end
  rescue
    error in ErlangError -> {:error, {:documentation_command_start_failed, phase, error.original}}
  end

  defp run(command, _, _, phase), do: {:error, {:invalid_documentation_command, phase, command}}

  defp remove_staging(path) do
    case File.rm_rf(Path.dirname(path)) do
      {:ok, _} -> :ok
      {:error, reason, failed} -> {:error, {:staging_cleanup_failed, failed, reason}}
    end
  end

  defp open_staging_parent(path) do
    parent = Path.dirname(path)

    if File.exists?(parent),
      do: {:error, {:occupied_staging_parent, parent}},
      else: File.mkdir(parent)
  end

  defp clean_checkout(repository) do
    case System.cmd(
           "git",
           ["-C", repository, "status", "--porcelain", "--untracked-files=no"],
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {"", 0} -> :ok
      {output, 0} -> {:error, {:documentation_build_changed_source, tail(output)}}
      {output, status} -> {:error, {:documentation_git_status_failed, status, tail(output)}}
    end
  end

  defp clean_collector(repository, repository), do: :ok
  defp clean_collector(repository, _), do: clean_checkout(repository)

  defp load_collection(source, artifact_dir) do
    with {:ok, descriptor} <- artifact_descriptor(artifact_dir),
         :ok <- descriptor_matches(source, descriptor) do
      descriptor = Map.put(descriptor, "artifact_dir", artifact_dir)
      DocShell.Generate.Collection.load(descriptor)
    end
  end

  defp artifact_descriptor(artifact_dir) do
    path = Path.join(artifact_dir, "collection.json")

    with {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size <= 4_194_304,
         {:ok, bytes} <- File.read(path),
         {:ok, %{"data" => %{"descriptor" => descriptor}}} <- JSON.decode(bytes),
         true <- is_map(descriptor) do
      {:ok, descriptor}
    else
      false -> {:error, :invalid_collection_descriptor_artifact}
      {:error, reason} -> {:error, {:invalid_collection_descriptor_artifact, reason}}
      _ -> {:error, :invalid_collection_descriptor_artifact}
    end
  end

  defp descriptor_matches(source, descriptor) do
    expected = %{
      "id" => String.replace(source["id"], "-", "_"),
      "version" => source["version"],
      "revision" => source["revision"],
      "tree_digest" => source["tree_digest"],
      "license" => source["license"],
      "source_root" => @source_root
    }

    package_matches =
      case source["kind"] do
        "mix_package" -> descriptor["package"] == source["hex_package"]
        "documentation" -> not Map.has_key?(descriptor, "package")
      end

    if Map.take(descriptor, Map.keys(expected)) == expected and package_matches,
      do: :ok,
      else: {:error, {:documentation_descriptor_mismatch, source["id"]}}
  end

  defp complete_admission(files, sources) do
    expected = MapSet.new(files)

    actual =
      sources
      |> Enum.flat_map(fn
        %{"source_path" => path} when is_binary(path) -> [path]
        _ -> []
      end)
      |> MapSet.new()

    if expected == actual do
      :ok
    else
      absent = missing(expected, actual)
      unexpected = missing(actual, expected)
      {:error, {:incomplete_documentation_admission, absent, unexpected}}
    end
  end

  defp expected_digest(%{"expected_collection_digest" => nil}, _), do: :ok

  defp expected_digest(%{"expected_collection_digest" => expected, "id" => id}, actual) do
    if expected == actual,
      do: :ok,
      else: {:error, {:collection_digest_mismatch, id, expected, actual}}
  end

  defp head(repository) do
    case System.cmd("git", ["-C", repository, "rev-parse", "HEAD"],
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {output, 0} -> {:ok, String.trim(output)}
      _ -> :error
    end
  end

  defp missing(left, right) do
    left
    |> MapSet.difference(right)
    |> Enum.sort()
  end

  defp tail(output) do
    output
    |> String.slice(-8_192, 8_192)
    |> String.trim()
  end
end
