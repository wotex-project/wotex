defmodule Wotex.Workspace.Impact do
  @moduledoc """
  The test files to run for a change to `MODULE` or `MODULE.FUN`.

  From the references to the target (Dexter, see `Wotex.Workspace.Dexter`):

    1. a reference in a test file (`packages/<name>/test/**/*_test.exs`)
       selects that file, listed as `direct`;
    2. a reference in a library file or a test support file selects, one
       hop away, every test file that references the module enclosing the
       reference, listed with that module;
    3. a package with a library reference (the definition of the target
       counts) for which neither rule selected a test file falls back to
       `mix test --stale`.

  References outside `packages/`, in dependencies or in other package files
  (`mix.exs`, `bin/`, `config/`) select nothing and are only counted. The
  reference source and the definition source are functions so that tests
  can supply fixture data; they default to Dexter.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Dexter
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.ModuleSpans
  alias Wotex.Workspace.References
  alias Wotex.Workspace.Steps

  @typedoc "Returns the locations for a module and an optional function."
  @type source :: (String.t(), String.t() | nil ->
                     {:ok, [Dexter.location()]} | {:error, String.t()})

  @type test_file :: %{file: Path.t(), via: [String.t()]}

  @type package_plan :: %{package: String.t(), tests: [test_file()], fallback: boolean()}

  @type t :: %{
          target: String.t(),
          references: [References.entry()],
          hops: [String.t()],
          unresolved: [References.entry()],
          ignored: non_neg_integer(),
          packages: [package_plan()]
        }

  @type option ::
          {:references, source()}
          | {:definitions, source()}
          | {:root, Path.t()}

  @doc """
  Plans the test files for `module` (and `fun`, when given).

  Options: `references:` and `definitions:` replace the Dexter queries;
  `root:` is where referencing source files are read.
  """
  @spec plan(String.t(), String.t() | nil, Manifest.t(), [option()]) ::
          {:ok, t()} | {:error, String.t()}
  def plan(module, fun, %Manifest{} = manifest, opts \\ []) do
    root = Keyword.get(opts, :root, Workspace.root())
    references = Keyword.get(opts, :references, &Dexter.references(&1, &2, root: root))
    definitions = Keyword.get(opts, :definitions, &Dexter.lookup(&1, &2, root: root))

    with {:ok, locations} <- references.(module, fun),
         {:ok, definition} <- definitions.(module, fun) do
      entries = Enum.map(locations, &References.classify/1)
      {relevant, ignored} = Enum.split_with(entries, &relevant?(&1, manifest))
      {direct, hop_sources} = Enum.split_with(relevant, &(&1.kind == :test))
      {hops, unresolved} = enclosing_modules(hop_sources, root)

      library =
        definition
        |> Enum.map(&References.classify/1)
        |> Kernel.++(relevant)
        |> Enum.filter(&(&1.kind == :lib))

      build(%{
        target: target(module, fun),
        references: relevant,
        hops: hops,
        unresolved: unresolved,
        ignored: length(ignored),
        direct: Enum.map(direct, &{&1.package, &1.package_file, "direct"}),
        library: library,
        source: references,
        manifest: manifest
      })
    end
  end

  @doc "`Module` or `Module.fun`."
  @spec target(String.t(), String.t() | nil) :: String.t()
  def target(module, nil), do: module
  def target(module, fun), do: "#{module}.#{fun}"

  @doc """
  The steps that run a plan: `mix test FILES...` per package, or `mix test
  --stale` for a package that falls back.
  """
  @spec targets(t(), Manifest.t()) :: [Steps.target()]
  def targets(plan, %Manifest{} = manifest) do
    Enum.map(plan.packages, fn
      %{package: name, fallback: true} ->
        step = {"test --stale", ["test", "--stale"], [mix_env: "test"]}
        Steps.target(name, manifest, [step], %{gate: "stale"})

      %{package: name, tests: tests} ->
        step = {"test", ["test" | Enum.map(tests, & &1.file)], [mix_env: "test"]}
        Steps.target(name, manifest, [step], %{gate: "files"})
    end)
  end

  @doc "Renders a plan for the terminal."
  @spec render(t()) :: String.t()
  def render(plan) do
    counts =
      plan.references
      |> Enum.frequencies_by(& &1.kind)
      |> Enum.sort()
      |> Enum.map_join(", ", fn {kind, count} -> "#{count} #{kind}" end)

    header =
      [
        "impact of #{plan.target}",
        "  references: #{if counts == "", do: "none", else: counts}" <>
          if(plan.ignored > 0, do: " (#{plan.ignored} outside package lib/test ignored)", else: ""),
        "  one hop through: #{if plan.hops == [], do: "none", else: Enum.join(plan.hops, ", ")}"
      ] ++ Enum.map(plan.unresolved, &"  no enclosing module for #{Dexter.format(&1)}")

    body = Enum.flat_map(plan.packages, &render_package/1)

    body =
      if body == [],
        do: ["", "no test files reference #{plan.target}"],
        else: body

    Enum.join(header ++ body, "\n") <> "\n"
  end

  defp build(%{hops: hops, source: source, manifest: manifest} = state) do
    with {:ok, hop_tests} <- hop_tests(hops, source, manifest) do
      {:ok,
       state
       |> Map.take([:target, :references, :hops, :unresolved, :ignored])
       |> Map.put(:packages, packages(state.direct ++ hop_tests, state.library, manifest))}
    end
  end

  defp render_package(%{package: name, fallback: true}) do
    [
      "",
      "#{name}: library references but no referencing test files; falls back to mix test --stale",
      "  mix pkg #{name} test --stale"
    ]
  end

  defp render_package(%{package: name, tests: tests}) do
    width = Enum.reduce(tests, 0, &max(&2, String.length(&1.file)))
    command = "  mix pkg #{name} test #{Enum.map_join(tests, " ", & &1.file)}"

    lines =
      Enum.map(tests, fn test ->
        "  #{String.pad_trailing(test.file, width)}  #{Enum.join(test.via, ", ")}"
      end)

    Enum.concat([["", "#{name} (#{length(tests)} test file(s))"], lines, [command]])
  end

  defp relevant?(%{package: package, kind: kind}, manifest) do
    is_binary(package) and Manifest.package?(package, manifest) and
      kind in [:lib, :support, :test]
  end

  # The sorted enclosing modules of `entries`; entries whose file cannot be
  # read or parsed, or that lie outside every module, are unresolved.
  defp enclosing_modules(entries, root) do
    {modules, unresolved} =
      Enum.reduce(entries, {MapSet.new(), []}, fn entry, {modules, unresolved} ->
        case enclosing_module(entry, root) do
          {:ok, module} -> {MapSet.put(modules, module), unresolved}
          :error -> {modules, [entry | unresolved]}
        end
      end)

    {Enum.sort(modules), Enum.reverse(unresolved)}
  end

  defp enclosing_module(entry, root) do
    with {:ok, source} <- File.read(Path.join(root, entry.file)),
         {:ok, module} when is_binary(module) <-
           ModuleSpans.enclosing(source, entry.line, entry.file) do
      {:ok, module}
    else
      _ -> :error
    end
  end

  defp hop_tests(modules, references, manifest) do
    Enum.reduce_while(modules, {:ok, []}, fn module, {:ok, acc} ->
      case references.(module, nil) do
        {:ok, locations} ->
          tests =
            for entry <- Enum.map(locations, &References.classify/1),
                entry.kind == :test and relevant?(entry, manifest),
                do: {entry.package, entry.package_file, module}

          {:cont, {:ok, acc ++ tests}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end)
  end

  defp packages(tests, library_entries, manifest) do
    by_package =
      tests
      |> Enum.group_by(fn {package, _, _} -> package end, fn {_, file, via} ->
        {file, via}
      end)
      |> Map.new(fn {package, files} -> {package, merge_via(files)} end)

    library = MapSet.new(library_entries, & &1.package)

    manifest.order
    |> Enum.filter(&(Map.has_key?(by_package, &1) or MapSet.member?(library, &1)))
    |> Enum.map(fn name ->
      case Map.get(by_package, name, []) do
        [] -> %{package: name, tests: [], fallback: true}
        files -> %{package: name, tests: files, fallback: false}
      end
    end)
  end

  defp merge_via(files) do
    files
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {file, via} ->
      via = Enum.sort_by(Enum.uniq(via), &{&1 != "direct", &1})
      %{file: file, via: via}
    end)
    |> Enum.sort_by(& &1.file)
  end
end
