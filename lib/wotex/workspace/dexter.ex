defmodule Wotex.Workspace.Dexter do
  @moduledoc """
  The Dexter code index of the repository (`.dexter/`, ignored).

  Dexter is pinned in the root `mise.toml` (`aqua:remoteoss/dexter`). The
  `dexter` executable is taken from `PATH` (mise shims or `mise x`); when it
  is not there, `mise x -- dexter` is tried. Every command runs with the
  repository root as working directory, and the absolute paths Dexter
  prints are returned repository-relative.

  `lookup/3` and `references/3` read the index as it is; callers that need
  fresh results run `reindex/1` first, which re-reads only the files that
  changed since the last run.
  """

  alias Wotex.Workspace

  @typedoc "A repository-relative file and a line."
  @type location :: %{file: Path.t(), line: pos_integer()}

  @type option ::
          {:root, Path.t()} | {:finder, (String.t() -> String.t() | nil)} | {:strict, boolean()}

  # Dexter needs no Mix or path-dependency settings of the caller.
  @env [{"MIX_ENV", nil}, {"WOTEX_PATH_DEPS", nil}]

  @install_hint "run `mise install` at the repository root; mise.toml pins aqua:remoteoss/dexter"

  @doc "The index database below `root`."
  @spec index_path(Path.t()) :: Path.t()
  def index_path(root \\ Workspace.root()), do: Path.join(root, ".dexter/dexter.db")

  @doc "Whether the index exists below `root`."
  @spec indexed?(Path.t()) :: boolean()
  def indexed?(root \\ Workspace.root()), do: File.regular?(index_path(root))

  @doc """
  The command that runs Dexter: `dexter` from `PATH`, else `mise x --
  dexter`. `finder` defaults to `System.find_executable/1`.
  """
  @spec command((String.t() -> String.t() | nil)) ::
          {:ok, {String.t(), [String.t()]}} | {:error, String.t()}
  def command(finder \\ &System.find_executable/1) do
    case finder.("dexter") do
      nil -> via_mise(finder.("mise"))
      dexter -> {:ok, {dexter, []}}
    end
  end

  @doc """
  Where `module` (and `fun`, when given) is defined. Dexter falls back to
  the module when the function is not found, unless `strict: true`; an
  unknown module yields `[]`.
  """
  @spec lookup(String.t(), String.t() | nil, [option()]) ::
          {:ok, [location()]} | {:error, String.t()}
  def lookup(module, fun \\ nil, opts \\ []) do
    strict = if Keyword.get(opts, :strict, false), do: ["--strict"], else: []

    with {:ok, output} <- query(["lookup", module | List.wrap(fun)] ++ strict, opts) do
      {:ok, parse_locations(output, roots(opts))}
    end
  end

  @doc "Every reference to `module` (and `fun`, when given)."
  @spec references(String.t(), String.t() | nil, [option()]) ::
          {:ok, [location()]} | {:error, String.t()}
  def references(module, fun \\ nil, opts \\ []) do
    with {:ok, output} <- query(["references", module | List.wrap(fun)], opts) do
      {:ok, parse_locations(output, roots(opts))}
    end
  end

  @doc """
  Re-indexes every file that changed since the last run. Fails when there
  is no index yet.
  """
  @spec reindex([option()]) :: :ok | {:error, String.t()}
  def reindex(opts \\ []) do
    root = Keyword.get(opts, :root, Workspace.root())

    if indexed?(root) do
      case run(["reindex"], opts) do
        {:ok, _} -> :ok
        {:error, {status, output}} -> {:error, failure(["reindex"], status, output)}
        {:error, message} -> {:error, message}
      end
    else
      {:error, "no Dexter index at #{Workspace.relative(index_path(root), root)}; run `mix index`"}
    end
  end

  @doc """
  Builds the index (`dexter init .`), or refreshes an existing one with
  `dexter reindex`. `force: true` deletes and rebuilds it. Dexter's output
  streams to the terminal.
  """
  @spec index(boolean(), [option()]) :: :ok | {:error, String.t()}
  def index(force? \\ false, opts \\ []) do
    root = Keyword.get(opts, :root, Workspace.root())

    args =
      cond do
        force? -> ["init", ".", "--force"]
        indexed?(root) -> ["reindex"]
        true -> ["init", "."]
      end

    with {:ok, {executable, prefix}} <- command(Keyword.get(opts, :finder, &find/1)) do
      Mix.shell().info(["==> ", Enum.join(["dexter" | args], " ")])

      case System.cmd(executable, prefix ++ args,
             cd: root,
             env: @env,
             into: IO.stream(),
             stderr_to_stdout: true
           ) do
        {_, 0} -> :ok
        {_, status} -> {:error, "dexter #{Enum.join(args, " ")} exited with #{status}"}
      end
    end
  end

  @doc """
  Parses Dexter's `path:line` lines into repository-relative locations,
  in output order without duplicates. Paths below none of `roots` stay
  absolute; other lines are ignored.
  """
  @spec parse_locations(String.t(), [Path.t()]) :: [location()]
  def parse_locations(output, roots) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^(.+):(\d+)$/, String.trim(line)) do
        [_, file, number] -> [%{file: relative(file, roots), line: String.to_integer(number)}]
        nil -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc "Formats a location as `path:line`."
  @spec format(location()) :: String.t()
  def format(%{file: file, line: line}), do: "#{file}:#{line}"

  defp query(args, opts) do
    case run(args, opts) do
      {:ok, output} -> {:ok, output}
      # `references` exits 1 when nothing refers to the target, `lookup
      # --strict` when there is no exact match.
      {:error, {1, ""}} -> {:ok, ""}
      {:error, {1, "No references found" <> _}} -> {:ok, ""}
      {:error, {status, output}} -> {:error, failure(args, status, output)}
      {:error, message} -> {:error, message}
    end
  end

  defp run(args, opts) do
    root = Keyword.get(opts, :root, Workspace.root())

    with {:ok, {executable, prefix}} <- command(Keyword.get(opts, :finder, &find/1)) do
      case System.cmd(executable, prefix ++ args, cd: root, env: @env, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, status} -> {:error, {status, String.trim(output)}}
      end
    end
  end

  defp failure(args, status, output) do
    hint = if output =~ ~r/mise|not installed|No version/i, do: "\n" <> @install_hint, else: ""
    "dexter #{Enum.join(args, " ")} exited with #{status}: #{String.trim(output)}#{hint}"
  end

  defp via_mise(nil), do: {:error, "dexter is not installed; " <> @install_hint}
  defp via_mise(mise), do: {:ok, {mise, ["x", "--", "dexter"]}}

  defp find(name), do: System.find_executable(name)

  # Dexter prints canonical paths; the root may be reached through a
  # symbolic link (/tmp on macOS), so both spellings are tried.
  defp roots(opts) do
    root = Keyword.get(opts, :root, Workspace.root())

    case System.cmd("pwd", ["-P"], cd: root, env: @env) do
      {canonical, 0} -> Enum.uniq([root, String.trim(canonical)])
      _ -> [root]
    end
  end

  defp relative(file, roots) do
    Enum.find_value(roots, file, fn root ->
      relative = Path.relative_to(file, root)
      if Path.type(relative) == :relative, do: relative
    end)
  end
end
