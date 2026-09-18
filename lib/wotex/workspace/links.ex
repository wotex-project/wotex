defmodule Wotex.Workspace.Links do
  @moduledoc """
  Link check over Markdown files.

  Every inline link or image (`[text](target)`, `![alt](target)`) and every
  reference definition (`[label]: target`) is checked, outside fenced code
  blocks and inline code spans:

    * a relative target has its `#anchor` and `?query` removed and its
      percent-escapes decoded, and must exist relative to the linking file,
      or relative to the repository root when it starts with `/`;
    * a URL into this repository's main branch
      (`https://github.com/wotex-project/wotex/blob/main/<path>` or
      `.../tree/main/<path>`) must name a path that exists in the working
      tree;
    * package documentation is published on HexDocs, which cannot resolve
      a relative link that leaves the package. In `docs/packages/<p>/**`
      and `packages/<p>/README.md`, a relative link to a `.md` file outside
      `docs/packages/<p>/` and `packages/<p>/` is reported; the fix is the
      main-branch URL above.

  Other URLs (`https:`, `mailto:`, ...) and anchor-only targets are
  skipped. Anchors themselves are not checked.
  """

  alias Wotex.Workspace

  @typedoc """
  A reported link. `problem` is `:missing` or `{:cross_package, path}`, where
  `path` is the repository-relative target that should be linked by URL.
  """
  @type broken :: %{
          file: Path.t(),
          line: pos_integer(),
          target: String.t(),
          problem: :missing | {:cross_package, Path.t()}
        }

  @main_url "https://github.com/wotex-project/wotex/blob/main/"

  @inline ~r/\]\(\s*(<[^>\n]*>|[^)\s]+(?:\([^)\s]*\)[^)\s]*)*)/
  @definition ~r/^\s{0,3}\[(?!\^)[^\]]+\]:\s+(<[^>\n]*>|\S+)/
  @repository_url ~r{^https://github\.com/wotex-project/wotex/(?:blob|tree)/main(?:/|$)}
  @scheme ~r/^[a-zA-Z][a-zA-Z0-9+.-]*:/
  @fence ~r/^\s{0,3}(```|~~~)/
  @machine_path ~r{(?:/Users/[A-Za-z]|/home/[a-z][a-z0-9_-]*/|/private/(?:tmp|var)/|/var/folders/)[^\s`"')\]]*}

  @doc "The Markdown files Git tracks below `root` (`git ls-files '*.md'`)."
  @spec tracked_markdown(Path.t()) :: {:ok, [Path.t()]} | {:error, String.t()}
  def tracked_markdown(root \\ Workspace.root()) do
    case System.cmd("git", ["ls-files", "-z", "--", "*.md"],
           cd: root,
           env: [{"GIT_OPTIONAL_LOCKS", "0"}],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, Enum.sort(String.split(output, <<0>>, trim: true))}
      {output, status} -> {:error, "git ls-files failed (#{status}): #{String.trim(output)}"}
    end
  end

  @doc """
  Checks the repository-relative Markdown `files` below `root` and returns
  every reported link. A listed file that no longer exists is skipped.
  """
  @spec check(Path.t(), [Path.t()]) :: [broken()]
  def check(root, files) do
    Enum.flat_map(files, fn file ->
      case File.read(Path.join(root, file)) do
        {:ok, text} ->
          for {line, target} <- links(text),
              problem = problem(root, file, target),
              do: %{file: file, line: line, target: target, problem: problem}

        {:error, _reason} ->
          []
      end
    end)
  end

  @doc """
  Absolute machine paths in the repository-relative Markdown `files` below
  `root`, as `{file, line, path}`. Tracked documentation names paths
  relative to the repository or uses a placeholder such as
  `/absolute/disposable/workspace`; a user home or a system temporary
  directory (`/Users/…`, `/home/<user>/…`, `/private/tmp/…`,
  `/private/var/…`, `/var/folders/…`) identifies one machine.
  """
  @spec machine_paths(Path.t(), [Path.t()]) :: [{Path.t(), pos_integer(), String.t()}]
  def machine_paths(root, files) do
    Enum.flat_map(files, fn file ->
      case File.read(Path.join(root, file)) do
        {:ok, text} ->
          text
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.flat_map(&line_machine_paths(file, &1))

        {:error, _reason} ->
          []
      end
    end)
  end

  # Sentence punctuation after a path is not part of it.
  defp line_machine_paths(file, {line, number}) do
    for [path] <- Regex.scan(@machine_path, line),
        do: {file, number, String.replace(path, ~r/[.,;:]+$/, "")}
  end

  @doc """
  The link targets of a Markdown text as `{line, target}`, outside fenced
  code blocks and inline code spans. Targets are returned as written.
  """
  @spec links(String.t()) :: [{pos_integer(), String.t()}]
  def links(text) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, fn {line, number}, {acc, fenced?} ->
      cond do
        Regex.match?(@fence, line) -> {acc, not fenced?}
        fenced? -> {acc, fenced?}
        true -> {Enum.reverse(line_links(line, number), acc), fenced?}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc """
  What a target in `file` refers to, as a repository-relative path:
  `{:relative, path}` for a relative link, `{:repository, path}` for a
  main-branch URL of this repository, `:skip` for other URLs and
  anchor-only targets.
  """
  @spec resolve(Path.t(), String.t()) :: {:relative | :repository, Path.t()} | :skip
  def resolve(file, target) do
    target = String.trim_trailing(String.trim_leading(target, "<"), ">")

    cond do
      Regex.match?(@repository_url, target) ->
        {:repository, path_part(String.replace(target, @repository_url, ""))}

      Regex.match?(@scheme, target) ->
        :skip

      true ->
        relative(file, path_part(target))
    end
  end

  @doc """
  The package whose HexDocs publish `file`: `p` for `docs/packages/<p>/**`
  and `packages/<p>/README.md`, else `nil`.
  """
  @spec published_package(Path.t()) :: String.t() | nil
  def published_package(file) do
    case Path.split(file) do
      ["docs", "packages", package, _first | _rest] -> package
      ["packages", package, "README.md"] -> package
      _other -> nil
    end
  end

  @doc "The main-branch URL of a repository-relative path."
  @spec main_url(Path.t()) :: String.t()
  def main_url(path), do: @main_url <> path

  @doc """
  Formats a reported link as `file:line: target`, with the URL to use for
  a link that leaves its package's documentation.
  """
  @spec format(broken()) :: String.t()
  def format(%{file: file, line: line, target: target, problem: :missing}),
    do: "#{file}:#{line}: #{target}"

  def format(%{file: file, line: line, target: target, problem: {:cross_package, path}}),
    do: "#{file}:#{line}: #{target} leaves the package documentation; link #{main_url(path)}"

  defp line_links(line, number) do
    line = Regex.replace(~r/(`+).*?\1/, line, "")

    inline = for [_match, target] <- Regex.scan(@inline, line), do: {number, target}

    definitions =
      case Regex.run(@definition, line) do
        [_match, target] -> [{number, target}]
        nil -> []
      end

    inline ++ definitions
  end

  defp problem(root, file, target) do
    case resolve(file, target) do
      :skip ->
        nil

      {:repository, path} ->
        unless File.exists?(Path.join(root, path)), do: :missing

      {:relative, path} ->
        cond do
          not File.exists?(Path.join(root, path)) -> :missing
          leaves_package?(file, path) -> {:cross_package, path}
          true -> nil
        end
    end
  end

  defp leaves_package?(file, path) do
    case published_package(file) do
      nil ->
        false

      package ->
        String.ends_with?(path, ".md") and
          not String.starts_with?(path, ["docs/packages/#{package}/", "packages/#{package}/"])
    end
  end

  defp relative(_file, ""), do: :skip
  defp relative(_file, "/" <> path), do: {:relative, normalize(path)}
  defp relative(file, path), do: {:relative, normalize(Path.join(Path.dirname(file), path))}

  # The path of a target: no `#anchor` or `?query`, percent-escapes decoded.
  defp path_part(target) do
    [path | _fragment] = String.split(target, ["#", "?"], parts: 2)
    decode(path)
  end

  defp decode(path) do
    URI.decode(path)
  rescue
    ArgumentError -> path
  end

  # Collapses `.` and `..` segments without touching the file system; a
  # path that climbs above the root keeps its leading `..`.
  defp normalize(path) do
    segments =
      path
      |> Path.split()
      |> Enum.reduce([], fn
        ".", acc -> acc
        "..", [previous | rest] when previous != ".." -> rest
        segment, acc -> [segment | acc]
      end)
      |> Enum.reverse()

    if segments == [], do: ".", else: Path.join(segments)
  end
end
