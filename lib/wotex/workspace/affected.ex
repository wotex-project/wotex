defmodule Wotex.Workspace.Affected do
  @moduledoc """
  Which packages a set of changed paths affects.

  Selection rules, applied to repository-relative paths:

    * a path under `packages/<name>/` selects that package;
    * a path under `docs/packages/<name>/` selects nothing (documentation
      only) unless `docs: true` is given, then it selects that package;
    * a path matching a `select_all_on` glob selects every package;
    * every transitive dependent of a selected package is selected too.

  The result is in the manifest's topological order. `classify/3` also marks
  each package: `:changed` when a changed path selects it directly (a
  `select_all_on` match marks every package `:changed`), `:dependent` when it
  is selected only as a transitive dependent of a changed package.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest

  @type option :: {:docs, boolean()}

  @typedoc "Why a package is affected."
  @type mark :: :changed | :dependent

  @doc """
  The affected package names for `changed_paths`, in topological order.
  """
  @spec affected(Manifest.t(), [Path.t()], [option()]) :: [String.t()]
  def affected(%Manifest{} = manifest, changed_paths, opts \\ []) do
    manifest
    |> classify(changed_paths, opts)
    |> Enum.map(fn {name, _} -> name end)
  end

  @doc """
  The affected packages for `changed_paths` in topological order, each
  marked `:changed` or `:dependent`.
  """
  @spec classify(Manifest.t(), [Path.t()], [option()]) :: [{String.t(), mark()}]
  def classify(%Manifest{} = manifest, changed_paths, opts \\ []) do
    case changed_packages(manifest, changed_paths, opts) do
      :all ->
        Enum.map(manifest.order, &{&1, :changed})

      changed ->
        selected = with_dependents(changed, manifest)

        for name <- manifest.order, MapSet.member?(selected, name) do
          {name, if(MapSet.member?(changed, name), do: :changed, else: :dependent)}
        end
    end
  end

  @doc "The names of `marked` packages, restricted to `mark` unless it is `nil`."
  @spec names([{String.t(), mark()}], mark() | nil) :: [String.t()]
  def names(marked, mark \\ nil) do
    for {name, package_mark} <- marked, mark in [nil, package_mark], do: name
  end

  @doc """
  Whether `path` matches any of the manifest's `select_all_on` globs.
  """
  @spec select_all?(Path.t(), [String.t()]) :: boolean()
  def select_all?(path, globs), do: Enum.any?(globs, &glob_match?(&1, path))

  @doc """
  Matches a glob against a repository-relative path.

  `**` matches any run of characters including `/`, `*` matches within one
  path segment and `?` matches one character. A trailing `/**` also matches
  the directory itself.
  """
  @spec glob_match?(String.t(), Path.t()) :: boolean()
  def glob_match?(glob, path) do
    Regex.match?(glob_regex(glob), normalize(path))
  end

  @doc """
  The paths changed since `base`: the committed difference `base...HEAD`
  plus the working tree (`git status --porcelain`). `base` defaults to
  `default_base/1`.
  """
  @spec changed_paths(String.t() | nil, Path.t()) :: {:ok, [Path.t()]} | {:error, String.t()}
  def changed_paths(base \\ nil, root \\ Workspace.root()) do
    with {:ok, base} <- resolve_base(base, root),
         {:ok, committed} <- git(["diff", "--name-only", "#{base}...HEAD"], root),
         {:ok, status} <- git(["status", "--porcelain", "--untracked-files=all"], root) do
      paths =
        (String.split(committed, "\n", trim: true) ++ porcelain_paths(status))
        |> Enum.map(&normalize/1)
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, paths}
    end
  end

  @doc """
  The default comparison base: `origin/main` if it exists, else `main`,
  else the repository's root commit.
  """
  @spec default_base(Path.t()) :: {:ok, String.t()} | {:error, String.t()}
  def default_base(root \\ Workspace.root()) do
    cond do
      ref?("origin/main", root) -> {:ok, "origin/main"}
      ref?("main", root) -> {:ok, "main"}
      true -> root_commit(root)
    end
  end

  @doc """
  Parses `git status --porcelain` output into changed paths. Renames yield
  the new path.
  """
  @spec porcelain_paths(String.t()) :: [Path.t()]
  def porcelain_paths(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn
      <<_::binary-size(2), " ", rest::binary>> ->
        case String.split(rest, " -> ", parts: 2) do
          [_, new] -> [unquote_path(new)]
          [path] -> [unquote_path(path)]
        end

      _ ->
        []
    end)
  end

  defp changed_packages(manifest, changed_paths, opts) do
    docs? = Keyword.get(opts, :docs, false)
    globs = manifest.select_all_on

    changed_paths
    |> Enum.map(&normalize/1)
    |> Enum.reduce_while(MapSet.new(), fn path, selected ->
      if select_all?(path, globs),
        do: {:halt, :all},
        else: {:cont, select_package(path, docs?, manifest, selected)}
    end)
  end

  defp select_package(path, docs?, manifest, selected) do
    case package_of(path, docs?) do
      {:ok, name} ->
        if Manifest.package?(name, manifest), do: MapSet.put(selected, name), else: selected

      :none ->
        selected
    end
  end

  defp package_of("packages/" <> rest, _), do: first_segment(rest)
  defp package_of("docs/packages/" <> rest, true), do: first_segment(rest)
  defp package_of(_, _), do: :none

  defp first_segment(rest) do
    case String.split(rest, "/", parts: 2) do
      [name, _] when name != "" -> {:ok, name}
      _ -> :none
    end
  end

  defp with_dependents(selected, manifest) do
    Enum.reduce(selected, selected, fn name, acc ->
      Enum.reduce(Manifest.transitive_dependents(name, manifest), acc, &MapSet.put(&2, &1))
    end)
  end

  defp glob_regex(glob) do
    {prefix, tail} =
      if String.ends_with?(glob, "/**"),
        do: {String.replace_suffix(glob, "/**", ""), "(/.*)?"},
        else: {glob, ""}

    body =
      prefix
      |> String.split(~r/(\*\*|\*|\?)/, include_captures: true)
      |> Enum.map_join(&translate_glob/1)

    Regex.compile!("^#{body}#{tail}$")
  end

  defp translate_glob("**"), do: ".*"
  defp translate_glob("*"), do: "[^/]*"
  defp translate_glob("?"), do: "[^/]"
  defp translate_glob(literal), do: Regex.escape(literal)

  defp normalize(path) do
    path
    |> String.trim()
    |> String.replace_prefix("./", "")
    |> String.trim_trailing("/")
  end

  defp unquote_path(path) do
    path = String.trim(path)

    if String.starts_with?(path, "\"") and String.ends_with?(path, "\""),
      do: String.slice(path, 1..-2//1),
      else: path
  end

  defp resolve_base(nil, root), do: default_base(root)
  defp resolve_base(base, _), do: {:ok, base}

  defp ref?(ref, root) do
    match?({:ok, _}, git(["rev-parse", "--verify", "--quiet", "#{ref}^{commit}"], root))
  end

  defp root_commit(root) do
    case git(["rev-list", "--max-parents=0", "HEAD"], root) do
      {:ok, output} ->
        case String.split(output, "\n", trim: true) do
          [first | _] -> {:ok, first}
          [] -> {:error, "the repository has no commits"}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  defp git(args, root) do
    env = [{"GIT_TERMINAL_PROMPT", "0"}, {"GIT_OPTIONAL_LOCKS", "0"}]

    case System.cmd("git", args, cd: root, env: env, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {output, status} ->
        {:error, "git #{Enum.join(args, " ")} failed (#{status}): #{String.trim(output)}"}
    end
  end
end
