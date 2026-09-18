defmodule Wotex.Workspace.NativeFiles do
  @moduledoc """
  The first-party native sources of a package.

  A package's C and C++ sources are the files below `packages/<name>/` that
  Git tracks, or that are untracked but not ignored, with a C or C++
  extension (`.c`, `.h`, `.cc`, `.cpp`, `.cxx`, `.hh`, `.hpp`, `.hxx`),
  minus every file matched by the root `.clang-format-ignore`. That file
  lists vendored and digest-pinned files; clang-format reads it too.

  `.clang-format-ignore` holds one repository-relative glob per line; blank
  lines and lines starting with `#` are skipped. `*` and `?` match within a
  path segment and `**` spans segments (`Wotex.Workspace.Affected.glob_match?/2`).
  Negated (`!`) patterns are refused rather than misread.

  `.h` files are C headers and `.hpp` files C++ headers: `language/1`
  decides which `.clang-format` section applies. The Rust crates of a
  package are its tracked `Cargo.toml` files outside ignored directories.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Affected

  @c_extensions ~w(.c .h)
  @cpp_extensions ~w(.cc .cpp .cxx .hh .hpp .hxx)
  @unit_extensions ~w(.c .cc .cpp .cxx)

  @ignore_file ".clang-format-ignore"

  @doc "The name of the exclusion file at the repository root."
  @spec ignore_file() :: String.t()
  def ignore_file, do: @ignore_file

  @doc "Whether `path` has a C or C++ extension."
  @spec c_family?(Path.t()) :: boolean()
  def c_family?(path), do: Path.extname(path) in (@c_extensions ++ @cpp_extensions)

  @doc "Whether `path` is a translation unit (a C or C++ source, not a header)."
  @spec translation_unit?(Path.t()) :: boolean()
  def translation_unit?(path), do: Path.extname(path) in @unit_extensions

  @doc "The `.clang-format` language section of `path`: `:c` for `.c` and `.h`, else `:cpp`."
  @spec language(Path.t()) :: :c | :cpp
  def language(path), do: if(Path.extname(path) in @c_extensions, do: :c, else: :cpp)

  @doc """
  Parses the text of `.clang-format-ignore` into its patterns.
  """
  @spec parse_ignore(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def parse_ignore(text) do
    patterns =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.map(&String.trim_leading(&1, "/"))

    case Enum.filter(patterns, &String.starts_with?(&1, "!")) do
      [] ->
        {:ok, patterns}

      negated ->
        {:error, "#{@ignore_file}: negated patterns are not supported: #{inspect(negated)}"}
    end
  end

  @doc "Reads and parses the root `.clang-format-ignore`; a missing file ignores nothing."
  @spec ignore_patterns(Path.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def ignore_patterns(root \\ Workspace.root()) do
    case File.read(Path.join(root, @ignore_file)) do
      {:ok, text} -> parse_ignore(text)
      {:error, :enoent} -> {:ok, []}
      {:error, reason} -> {:error, "#{@ignore_file}: #{:file.format_error(reason)}"}
    end
  end

  @doc "Whether repository-relative `path` matches any ignore pattern."
  @spec ignored?(Path.t(), [String.t()]) :: boolean()
  def ignored?(path, patterns), do: Enum.any?(patterns, &Affected.glob_match?(&1, path))

  @doc """
  Selects the first-party C and C++ files among repository-relative `paths`.
  """
  @spec select([Path.t()], [String.t()]) :: [Path.t()]
  def select(paths, patterns) do
    paths
    |> Enum.filter(&(c_family?(&1) and not ignored?(&1, patterns)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  The tracked Rust crate manifests among repository-relative `paths`: every
  `Cargo.toml` not matched by an ignore pattern.
  """
  @spec crates([Path.t()], [String.t()]) :: [Path.t()]
  def crates(paths, patterns) do
    paths
    |> Enum.filter(&(Path.basename(&1) == "Cargo.toml" and not ignored?(&1, patterns)))
    |> Enum.sort()
  end

  @doc """
  The files below repository-relative `directory` that Git tracks, plus the
  untracked files that are not ignored, repository-relative and sorted.
  """
  @spec listed(Path.t(), Path.t()) :: {:ok, [Path.t()]} | {:error, String.t()}
  def listed(directory, root \\ Workspace.root()) do
    args = ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", directory]

    case System.cmd("git", args,
           cd: root,
           env: [{"GIT_OPTIONAL_LOCKS", "0"}],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        files =
          output
          |> String.split(<<0>>, trim: true)
          |> Enum.filter(&File.regular?(Path.join(root, &1)))
          |> Enum.uniq()
          |> Enum.sort()

        {:ok, files}

      {output, status} ->
        {:error, "git ls-files failed (#{status}): #{String.trim(output)}"}
    end
  end

  @doc """
  The first-party C and C++ files and the Rust crate manifests of the
  package directory `directory` (repository-relative).
  """
  @spec package(Path.t(), Path.t()) ::
          {:ok, %{sources: [Path.t()], crates: [Path.t()], files: [Path.t()]}}
          | {:error, String.t()}
  def package(directory, root \\ Workspace.root()) do
    with {:ok, patterns} <- ignore_patterns(root),
         {:ok, files} <- listed(directory, root) do
      {:ok, %{sources: select(files, patterns), crates: crates(files, patterns), files: files}}
    end
  end
end
