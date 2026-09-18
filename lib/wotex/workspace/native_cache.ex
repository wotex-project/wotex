defmodule Wotex.Workspace.NativeCache do
  @moduledoc """
  Build workspaces for the native checks, outside the repository.

  A suite with a `build` task needs that task's workspace. Unless the caller
  names one with `--workspace`, it lives at

      <cache>/<package>/<suite>/<key>

  where `<cache>` is `$WOTEX_NATIVE_CACHE`, else `wotex-native` in the system
  temporary directory, with symbolic links resolved (some build tasks refuse
  a workspace below a link, and macOS links `/var` to `/private/var`). `<key>`
  is `key/2`: a digest of every file of the package that Git tracks or does
  not ignore, except Markdown (path and content), and of the suite's name
  and build task; its other keys (compile and test commands, containers) do
  not change what the build produces. Package build
  tasks reuse a workspace whose recorded inputs match and refuse any other,
  so the first run builds, later runs of the same sources reuse it, and a
  change selects a new workspace. Workspaces of older keys are removed after
  a successful build. Markdown files are left out of the key, so a
  documentation change keeps the workspace; a build task that still sees a
  change refuses the workspace, which is then rebuilt
  (`Wotex.Workspace.NativeCheck`).

  Every suite also gets `<cache>/<package>/<suite>/scratch`, emptied before
  each run, for compile databases and test builds.
  """

  alias Wotex.Workspace.NativeSuite

  @variable "WOTEX_NATIVE_CACHE"

  @doc "The environment variable that relocates the cache."
  @spec variable() :: String.t()
  def variable, do: @variable

  @doc "The cache root: `$WOTEX_NATIVE_CACHE`, else `<tmp>/wotex-native`, links resolved."
  @spec root((String.t() -> String.t() | nil)) :: Path.t()
  def root(env \\ &System.get_env/1) do
    base =
      case env.(@variable) do
        value when value in [nil, ""] -> Path.join(System.tmp_dir!(), "wotex-native")
        value -> Path.expand(value)
      end

    real_path(base)
  end

  @doc "The directory of a package's suite below `cache`."
  @spec suite_dir(Path.t(), String.t(), NativeSuite.t()) :: Path.t()
  def suite_dir(cache, package, %NativeSuite{name: name}), do: Path.join([cache, package, name])

  @doc """
  The cache key of a suite's workspace: the first 16 hex digits of a
  SHA-256 over the suite's name and build task and every `{relative_path,
  content_digest}` of `digests`.
  """
  @spec key(NativeSuite.t(), [{Path.t(), binary()}]) :: String.t()
  def key(%NativeSuite{name: name, build: build}, digests) do
    material = :erlang.term_to_binary({name, build, Enum.sort(digests)})
    digest = Base.encode16(:crypto.hash(:sha256, material), case: :lower)
    binary_part(digest, 0, 16)
  end

  @doc """
  The `{relative_path, sha256}` pairs of repository-relative `files`
  below `root`, relative to `package_dir`; Markdown files are left out.
  """
  @spec digests([Path.t()], Path.t(), Path.t()) :: [{Path.t(), binary()}]
  def digests(files, package_dir, root) do
    for file <- files,
        Path.extname(file) != ".md",
        absolute = Path.join(root, file),
        File.regular?(absolute),
        do: {Path.relative_to(absolute, package_dir), :crypto.hash(:sha256, File.read!(absolute))}
  end

  @doc """
  Removes every entry of `suite_dir` other than the workspace `keep`, its
  lock sibling (`<keep>.lock`) and `scratch`.
  """
  @spec prune(Path.t(), String.t()) :: :ok
  def prune(suite_dir, keep) do
    case File.ls(suite_dir) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&(&1 in [keep, keep <> ".lock", "scratch"]))
        |> Enum.each(&File.rm_rf!(Path.join(suite_dir, &1)))

      {:error, _reason} ->
        :ok
    end
  end

  @doc "Empties (creates) a directory."
  @spec reset!(Path.t()) :: Path.t()
  def reset!(directory) do
    File.rm_rf!(directory)
    File.mkdir_p!(directory)
    directory
  end

  @doc """
  `path` with every symbolic link resolved, component by component; missing
  trailing components are kept as they are.
  """
  @spec real_path(Path.t()) :: Path.t()
  def real_path(path) do
    path
    |> Path.expand()
    |> Path.split()
    |> Enum.reduce("/", &resolve_component/2)
  end

  defp resolve_component("/", "/"), do: "/"

  defp resolve_component(component, resolved) do
    candidate = Path.join(resolved, component)

    case File.read_link(candidate) do
      {:ok, target} -> real_path(Path.expand(target, resolved))
      {:error, _reason} -> candidate
    end
  end
end
