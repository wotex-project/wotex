defmodule Wotex.Workspace.NativeTidy do
  @moduledoc """
  Runs clang-tidy over translation units, in parallel, and remembers the
  units it found clean.

  Each unit is one clang-tidy process, on the host or in a container
  (`Wotex.Workspace.NativeContainer`). A unit is clean when clang-tidy
  exits with status 0 and reports no warning. A clean unit is recorded in
  the package's result directory (`<cache>/<package>/tidy/results`, one
  file per unit) under its key: a SHA-256 over

    * the shared inputs of the run (`material:`): the clang-tidy version,
      the digest of the root `.clang-tidy`, the digest of every first-party
      header of the package and, for a container, its image and volumes;
    * the unit's compile command and its clang-tidy command line (without
      the `docker exec` of a container, whose name differs on every run);
    * the content of the unit.

  A later run that computes the same key reuses the result instead of
  running clang-tidy. Findings are never recorded, so a unit with findings
  is analysed, and reported, on every run until it is clean.
  """

  @typedoc """
  One translation unit: `path` (repository-relative, for messages),
  `source` (the file whose content is part of the key), `entry` (its
  compile command), `tidy` (the clang-tidy arguments, part of the key) and
  `argv` (the command that analyses it, on the host or through `docker
  exec`).
  """
  @type unit :: %{
          required(:path) => Path.t(),
          required(:source) => Path.t(),
          required(:entry) => map(),
          required(:tidy) => [String.t()],
          required(:argv) => [String.t()],
          optional(atom()) => term()
        }

  @typedoc "What a run analysed: unit counts and the paths of units with findings."
  @type result :: %{units: non_neg_integer(), reused: non_neg_integer(), failed: [Path.t()]}

  @type option ::
          {:results, Path.t()}
          | {:material, term()}
          | {:cd, Path.t()}
          | {:env, [{String.t(), String.t() | nil}]}
          | {:translate, (unit(), String.t() -> String.t())}
          | {:concurrency, pos_integer()}

  @doc """
  Analyses `units`. Needs `results:` (the result directory) and
  `material:` (the shared key inputs); `cd:` and `env:` apply to every
  command, `translate:` rewrites a unit's reported output (container paths) and
  `concurrency:` bounds the parallel processes (default: schedulers).
  """
  @spec run([unit()], [option()]) :: result()
  def run(units, opts) do
    results = Keyword.fetch!(opts, :results)
    material = Keyword.fetch!(opts, :material)
    translate = Keyword.get(opts, :translate, fn _unit, text -> text end)

    keyed = Enum.map(units, &{&1, key(material, &1)})
    {reused, pending} = Enum.split_with(keyed, fn {unit, key} -> recorded?(results, unit, key) end)

    failed =
      pending
      |> Task.async_stream(fn {unit, key} -> {unit, key, execute(unit.argv, opts)} end,
        max_concurrency: Keyword.get(opts, :concurrency, System.schedulers_online()),
        timeout: :infinity,
        ordered: true
      )
      |> Enum.flat_map(fn {:ok, {unit, key, {output, status}}} ->
        if status == 0 and not String.contains?(output, "warning:") do
          record(results, unit, key)
          []
        else
          forget(results, unit)
          Mix.shell().error(translate.(unit, String.trim(output)))
          [unit.path]
        end
      end)

    %{units: length(units), reused: length(reused), failed: failed}
  end

  @doc "The key of `unit` under the shared inputs `material`."
  @spec key(term(), unit()) :: String.t()
  def key(material, unit) do
    content = :crypto.hash(:sha256, File.read!(unit.source))
    term = {material, unit.entry, unit.tidy, content}
    Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic])))
  end

  defp execute([executable | args], opts) do
    System.cmd(executable, args,
      cd: Keyword.get(opts, :cd, File.cwd!()),
      env: Keyword.get(opts, :env, []),
      stderr_to_stdout: true
    )
  rescue
    error in ErlangError -> {"#{executable}: #{Exception.message(error)}", 127}
  end

  defp record_path(results, unit) do
    name = Base.encode16(:crypto.hash(:sha256, unit.path), case: :lower)
    Path.join(results, binary_part(name, 0, 24))
  end

  defp recorded?(results, unit, key), do: File.read(record_path(results, unit)) == {:ok, key}

  defp record(results, unit, key) do
    File.mkdir_p!(results)
    File.write!(record_path(results, unit), key)
  end

  defp forget(results, unit), do: File.rm(record_path(results, unit))
end
