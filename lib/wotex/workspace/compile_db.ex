defmodule Wotex.Workspace.CompileDb do
  @moduledoc """
  Compilation databases (`compile_commands.json`) for clang-tidy.

  A suite's database is the union of the databases its build or `prepare`
  commands wrote (CMake with `CMAKE_EXPORT_COMPILE_COMMANDS`, `ninja -t
  compdb`) and entries synthesized from its `compile` flags for files that
  are compiled by a Mix task or an ExUnit test rather than a build system.
  Entries are keyed by the file's real path, so a database that names a file
  through a symbolic link (a `_build/.../priv` link) still matches the file
  in `packages/`. The first entry for a file wins.
  """

  alias Wotex.Workspace.NativeCache
  alias Wotex.Workspace.NativeFiles

  @type entry :: %{String.t() => term()}

  @doc "Reads a `compile_commands.json` file."
  @spec read(Path.t()) :: {:ok, [entry()]} | {:error, String.t()}
  def read(path) do
    with {:ok, text} <- File.read(path),
         {:ok, entries} when is_list(entries) <- JSON.decode(text) do
      {:ok, Enum.filter(entries, &valid?/1)}
    else
      {:error, reason} when is_atom(reason) -> {:error, "#{path}: #{:file.format_error(reason)}"}
      _ -> {:error, "#{path}: not a compilation database"}
    end
  end

  @doc """
  A synthesized entry for absolute `file`: the C or C++ driver (`cc` or
  `c++`), `flags` and `-c file`, run in `directory`.
  """
  @spec entry(Path.t(), [String.t()], Path.t()) :: entry()
  def entry(file, flags, directory) do
    compiler = if NativeFiles.language(file) == :c, do: "cc", else: "c++"
    %{"directory" => directory, "file" => file, "arguments" => [compiler | flags] ++ ["-c", file]}
  end

  @doc """
  Merges entry lists, keeping the first entry per real file path, and
  rewrites each entry's `file` to that real path.
  """
  @spec merge([[entry()]]) :: [entry()]
  def merge(lists) do
    lists
    |> Enum.concat()
    |> Enum.map(fn entry -> Map.put(entry, "file", real_file(entry)) end)
    |> Enum.uniq_by(& &1["file"])
  end

  @doc "The real paths of the files an entry list covers."
  @spec files([entry()]) :: MapSet.t(Path.t())
  def files(entries), do: MapSet.new(entries, & &1["file"])

  @doc "Writes `entries` as `<directory>/compile_commands.json`."
  @spec write!(Path.t(), [entry()]) :: Path.t()
  def write!(directory, entries) do
    File.mkdir_p!(directory)
    path = Path.join(directory, "compile_commands.json")
    File.write!(path, JSON.encode!(entries))
    path
  end

  defp valid?(%{"file" => file, "directory" => directory} = entry)
       when is_binary(file) and is_binary(directory),
       do: is_binary(entry["command"]) or is_list(entry["arguments"])

  defp valid?(_), do: false

  defp real_file(%{"file" => file, "directory" => directory}),
    do: NativeCache.real_path(Path.expand(file, directory))
end
