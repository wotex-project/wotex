defmodule Mix.Tasks.Wotex.Native.Test do
  @shortdoc "Runs the native tests of the changed packages"

  @moduledoc """
  Runs the native tests of the selected packages. The root alias is
  `mix native.test`.

      mix wotex.native.test [--all] [--package NAME]... [--base REF] [--workspace /abs/dir]

  For each selected package with native code (default: the changed
  packages):

    * `cargo test --all-features --locked` for each Rust crate;
    * for each `native_check` suite in `tooling/packages.yaml`: its build
      task, in a cached workspace outside the repository
      (`Wotex.Workspace.NativeCache`) or in `--workspace /abs/dir` (needs
      exactly one `--package`), then its test commands (CTest, the test
      executables the build produced, or ExUnit files tagged for the native
      lane).

  A suite whose host requirements are not met fails with a message. Every
  package runs; a summary table follows and the task fails when any step
  failed.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeCheck
  alias Wotex.Workspace.Report

  @switches [workspace: :string] ++ CLI.selection_switches()

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()

    contexts =
      manifest
      |> CLI.select!(opts, :changed)
      |> Enum.filter(&Manifest.fetch!(&1, manifest).native)
      |> Enum.map(&context!(&1, manifest))

    if contexts == [], do: Mix.shell().info("no changed packages with native code")

    rows =
      for context <- contexts, {step, fun} <- plan(context, opts) do
        {result, seconds} = CLI.timed(fun)
        %{package: context.name, step: step, result: to_string(result), seconds: seconds}
      end

    if rows != [],
      do: Mix.shell().info("\n" <> Report.table(rows, [:package, :step, :result, :seconds]))

    if Enum.any?(rows, &(&1.result != "ok")), do: CLI.fail("native tests failed")
    :ok
  end

  @doc "Parses the task's options; `--workspace` needs an absolute path and exactly one `--package`."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    if workspace = opts[:workspace] do
      cond do
        Path.type(workspace) != :absolute ->
          Mix.raise("--workspace must be an absolute directory")

        length(Keyword.get_values(opts, :package)) != 1 ->
          Mix.raise("--workspace needs exactly one --package")

        true ->
          :ok
      end
    end

    opts
  end

  @doc "The step labels for a package with `crates` and `suites` names."
  @spec steps([Path.t()], [String.t()]) :: [String.t()]
  def steps(crates, suites) do
    Enum.map(crates, fn _ -> "cargo test" end)
    |> Enum.uniq()
    |> Kernel.++(Enum.map(suites, &"suite #{&1}"))
  end

  defp context!(name, manifest) do
    case NativeCheck.context(name, manifest) do
      {:ok, context} -> context
      {:error, message} -> CLI.fail(message)
    end
  end

  defp plan(context, opts) do
    check = [workspace: opts[:workspace]]

    rust =
      if context.crates != [],
        do: [{"cargo test", fn -> NativeCheck.rust(context, :test, check) end}],
        else: []

    suites =
      for suite <- context.suites do
        {"suite #{suite.name}", fn -> NativeCheck.test(%{context | suites: [suite]}, check) end}
      end

    rust ++ suites
  end
end
