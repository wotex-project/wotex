defmodule Mix.Tasks.Wotex.Native.Suite do
  @shortdoc "Runs one native_check suite of a package"

  @moduledoc """
  Runs one `native_check` suite of a package (`tooling/packages.yaml`):

      mix wotex.native.suite --package NAME --suite NAME --tidy
                             [--exclude UNIT]... [--result FILE] [--workspace /abs/dir]
      mix wotex.native.suite --package NAME --suite NAME --test [--workspace /abs/dir]

  `--tidy` runs clang-tidy on the first-party translation units the suite's
  compile commands cover, less each `--exclude` (repository-relative), and
  writes `{"status": "ok" | "error", "analysed": [units]}` to `--result`
  once clang-tidy ran. `--test` runs the suite's build task and test
  commands. `--workspace` names the build task's workspace instead of the
  cached one (`Wotex.Workspace.NativeCache`).

  The suites are the package's `native_check` suites and the compile-only
  suites of its `nanobench` drivers (`bench-<id>`,
  `Wotex.Workspace.NativeCheck.suites/1`). The Linux container of the native
  checks runs this task for a suite that requires Linux
  (`Wotex.Workspace.NativeContainer`); `mix native.lint --tidy` and
  `mix native.test` run every suite of a package.
  """

  use Mix.Task

  alias Wotex.Workspace
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeCache
  alias Wotex.Workspace.NativeCheck
  alias Wotex.Workspace.NativeTools

  @switches [
    package: :string,
    suite: :string,
    tidy: :boolean,
    test: :boolean,
    exclude: :keep,
    result: :string,
    workspace: :string
  ]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()
    package = CLI.package!(manifest, opts[:package])

    context =
      case NativeCheck.context(package, manifest) do
        {:ok, context} -> context
        {:error, message} -> CLI.fail(message)
      end

    suite =
      Enum.find(NativeCheck.suites(context), &(&1.name == opts[:suite])) ||
        CLI.fail("package #{package} has no native_check suite #{inspect(opts[:suite])}")

    check = [workspace: opts[:workspace]]

    if opts[:tidy] do
      tidy(context, suite, check, opts)
    else
      if NativeCheck.test(%{context | suites: [suite]}, check) != :ok,
        do: CLI.fail("#{package} suite #{suite.name}: native tests failed")

      :ok
    end
  end

  @doc """
  Parses the task's options: `--package`, `--suite` and exactly one of
  `--tidy` and `--test` are required; `--workspace` must be absolute.
  """
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    cond do
      opts[:package] in [nil, ""] ->
        Mix.raise("--package NAME is required")

      opts[:suite] in [nil, ""] ->
        Mix.raise("--suite NAME is required")

      Keyword.get(opts, :tidy, false) == Keyword.get(opts, :test, false) ->
        Mix.raise("pass exactly one of --tidy and --test")

      opts[:workspace] && Path.type(opts[:workspace]) != :absolute ->
        Mix.raise("--workspace must be an absolute directory")

      true ->
        opts
    end
  end

  defp tidy(context, suite, check, opts) do
    tool =
      case NativeTools.find(:clang_tidy) do
        {:ok, found} -> found
        {:error, message} -> CLI.fail(message)
      end

    covered =
      MapSet.new(
        Keyword.get_values(opts, :exclude),
        &NativeCache.real_path(Path.join(context.root, &1))
      )

    case NativeCheck.tidy_suite(context, suite, [tool: tool, covered: covered] ++ check) do
      {:analysed, paths, outcome} ->
        write_result(opts[:result], context.root, paths, outcome)
        if outcome != :ok, do: CLI.fail("#{context.name} suite #{suite.name}: clang-tidy findings")
        :ok

      :error ->
        CLI.fail("#{context.name} suite #{suite.name} did not run")
    end
  end

  defp write_result(nil, _, _, _), do: :ok

  defp write_result(file, root, paths, outcome) do
    root = NativeCache.real_path(root)
    analysed = Enum.sort(Enum.map(paths, &Workspace.relative(&1, root)))
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, JSON.encode!(%{"status" => Atom.to_string(outcome), "analysed" => analysed}))
  end
end
