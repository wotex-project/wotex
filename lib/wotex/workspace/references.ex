defmodule Wotex.Workspace.References do
  @moduledoc """
  Classifies repository-relative code locations by package and by kind, and
  renders them grouped.

  Kinds, by path inside a package directory (or inside the root project for
  paths outside `packages/`):

    * `:lib` - below `lib/`;
    * `:test` - a `*_test.exs` file below `test/`;
    * `:support` - any other file below `test/` (test support modules);
    * `:dependency` - below `deps/` or `_build/`, or outside the repository;
    * `:other` - anything else (`mix.exs`, `bin/`, `config/`, ...).
  """

  alias Wotex.Workspace.Dexter
  alias Wotex.Workspace.Manifest

  @type kind :: :lib | :test | :support | :dependency | :other

  @typedoc """
  A classified location. `package` is `nil` outside `packages/`;
  `package_file` is the path relative to the package directory (or the
  repository root outside `packages/`).
  """
  @type entry :: %{
          file: Path.t(),
          line: pos_integer(),
          package: String.t() | nil,
          package_file: Path.t(),
          kind: kind()
        }

  @kinds [:lib, :support, :test, :other]

  @doc "Classifies one location."
  @spec classify(Dexter.location()) :: entry()
  def classify(%{file: file, line: line}) do
    {package, package_file} = split_package(file)

    kind =
      if Path.type(file) == :absolute,
        do: :dependency,
        else: kind_of(package_file)

    %{file: file, line: line, package: package, package_file: package_file, kind: kind}
  end

  @doc """
  Splits a repository-relative path into its package and the path inside
  the package: `packages/a/lib/x.ex` gives `{"a", "lib/x.ex"}`, a path
  outside `packages/` gives `{nil, path}`.
  """
  @spec split_package(Path.t()) :: {String.t() | nil, Path.t()}
  def split_package("packages/" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [name, inside] when name != "" and inside != "" -> {name, inside}
      _ -> {nil, "packages/" <> rest}
    end
  end

  def split_package(path), do: {nil, path}

  @doc """
  Groups entries by package in the manifest's order, packages outside the
  manifest and the root project (`nil`) last. Dependency entries are
  dropped; the second element counts them.
  """
  @spec group([entry()], Manifest.t()) :: {[{String.t() | nil, [entry()]}], non_neg_integer()}
  def group(entries, %Manifest{} = manifest) do
    {dependencies, entries} = Enum.split_with(entries, &(&1.kind == :dependency))
    rank = Map.new(Enum.with_index(manifest.order))
    last = map_size(rank)

    groups =
      entries
      |> Enum.group_by(& &1.package)
      |> Enum.sort_by(fn {package, _} ->
        {if(package, do: Map.get(rank, package, last), else: last + 1), package || ""}
      end)
      |> Enum.map(fn {package, entries} -> {package, sort(entries)} end)

    {groups, length(dependencies)}
  end

  @doc """
  Renders references grouped by package and kind, one repository-relative
  `path:line` per line.
  """
  @spec render(String.t(), [entry()], Manifest.t()) :: String.t()
  def render(title, entries, %Manifest{} = manifest) do
    {groups, dependencies} = group(entries, manifest)
    count = length(entries) - dependencies

    header = "#{title}: #{count} reference(s)"

    footer =
      if dependencies > 0,
        do: ["", "#{dependencies} reference(s) in dependencies (deps/, _build/) not shown"],
        else: []

    body =
      Enum.flat_map(groups, fn {package, entries} ->
        ["", package || "(workspace root)"] ++
          Enum.map(entries, fn entry ->
            "  " <> String.pad_trailing(Atom.to_string(entry.kind), 8) <> Dexter.format(entry)
          end)
      end)

    Enum.join([header | body] ++ footer, "\n") <> "\n"
  end

  defp kind_of(path) do
    cond do
      String.starts_with?(path, ["deps/", "_build/"]) -> :dependency
      String.starts_with?(path, "lib/") -> :lib
      String.starts_with?(path, "test/") and String.ends_with?(path, "_test.exs") -> :test
      String.starts_with?(path, "test/") -> :support
      true -> :other
    end
  end

  defp sort(entries) do
    Enum.sort_by(entries, fn entry ->
      {Enum.find_index(@kinds, &(&1 == entry.kind)), entry.file, entry.line}
    end)
  end
end
