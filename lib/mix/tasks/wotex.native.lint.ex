defmodule Mix.Tasks.Wotex.Native.Lint do
  @shortdoc "Formats and lints first-party C, C++ and Rust code"

  @moduledoc """
  Checks the first-party native code of the selected packages. The root
  alias is `mix native.lint`.

      mix wotex.native.lint [--all] [--package NAME]... [--base REF] [--fix]
                            [--tidy [--workspace /abs/dir]] [--no-format] [--no-clippy]

  For each selected package with native code (default: the changed
  packages, see `mix wotex.affected --detail`):

    * **format**: clang-format with the root `.clang-format` on the C and
      C++ lines changed since the merge base of `--base` (default
      `origin/main`, else `main`) and `HEAD`, including uncommitted and
      untracked files (`Wotex.Workspace.ChangedLines`); `cargo fmt --check`
      for each Rust crate. `--fix` rewrites instead of checking.
      `--no-format` leaves this out.
    * **clippy**: `cargo clippy --all-targets --all-features --locked -- -D
      warnings` for each Rust crate. `--no-clippy` leaves this out.
    * **tidy** (only with `--tidy`): clang-tidy with the root `.clang-tidy` on
      every first-party translation unit, using the compile commands of the
      package's `native_check` suites in `tooling/packages.yaml`. Suites with
      a build task build into a cached workspace outside the repository
      (`Wotex.Workspace.NativeCache`), or into `--workspace /abs/dir`, which
      must be that task's workspace and needs exactly one `--package`.

  Vendored and pinned files listed in `.clang-format-ignore` are never
  checked. clang-format and clang-tidy come from `CLANG_FORMAT`/`CLANG_TIDY`,
  `PATH` or an LLVM prefix and must be version 22 or later
  (`Wotex.Workspace.NativeTools`). Every package runs; a summary table
  follows and the task fails when any step failed.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeCheck
  alias Wotex.Workspace.NativeTools
  alias Wotex.Workspace.Report

  @switches [
              fix: :boolean,
              tidy: :boolean,
              workspace: :string,
              format: :boolean,
              clippy: :boolean
            ] ++ CLI.selection_switches()

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()
    contexts = contexts(manifest, opts)
    if contexts == [], do: Mix.shell().info("no changed packages with native code")

    tools = tools(contexts, opts)

    rows =
      for context <- contexts, {step, fun} <- plan(context, opts, tools) do
        {result, seconds} = CLI.timed(fun)
        %{package: context.name, step: step, result: to_string(result), seconds: seconds}
      end

    if rows != [],
      do: Mix.shell().info("\n" <> Report.table(rows, [:package, :step, :result, :seconds]))

    if Enum.any?(rows, &(&1.result != "ok")), do: CLI.fail("native lint failed")
    :ok
  end

  @doc """
  Parses the task's options. `--workspace` needs `--tidy`, an absolute path
  and exactly one `--package`.
  """
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    if workspace = opts[:workspace] do
      cond do
        not Keyword.get(opts, :tidy, false) ->
          Mix.raise("--workspace needs --tidy")

        Path.type(workspace) != :absolute ->
          Mix.raise("--workspace must be an absolute directory")

        length(Keyword.get_values(opts, :package)) != 1 ->
          Mix.raise("--workspace needs exactly one --package")

        true ->
          :ok
      end
    end

    if opts[:fix] && opts[:tidy], do: Mix.raise("--fix applies formatting; run --tidy separately")
    opts
  end

  @doc """
  The steps for a package with `kinds` (see `Wotex.Workspace.NativeCheck.kinds/1`)
  under `opts`, as labels in order.
  """
  @spec steps(%{c_family: boolean(), rust: boolean()}, keyword()) :: [String.t()]
  def steps(kinds, opts) do
    format? = Keyword.get(opts, :format, true)
    clippy? = Keyword.get(opts, :clippy, true)
    tidy? = Keyword.get(opts, :tidy, false)

    [
      {"clang-format", format? and kinds.c_family},
      {"rustfmt", format? and kinds.rust},
      {"clippy", clippy? and kinds.rust},
      {"clang-tidy", tidy? and kinds.c_family}
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  defp contexts(manifest, opts) do
    manifest
    |> CLI.select!(opts, :changed)
    |> Enum.filter(&Manifest.fetch!(&1, manifest).native)
    |> Enum.map(fn name ->
      case NativeCheck.context(name, manifest) do
        {:ok, context} -> context
        {:error, message} -> CLI.fail(message)
      end
    end)
  end

  defp tools(contexts, opts) do
    needs = MapSet.new(Enum.flat_map(contexts, &steps(NativeCheck.kinds(&1), opts)))

    for {step, tool} <- [{"clang-format", :clang_format}, {"clang-tidy", :clang_tidy}],
        MapSet.member?(needs, step),
        into: %{} do
      case NativeTools.find(tool) do
        {:ok, found} -> {step, found}
        {:error, message} -> CLI.fail(message)
      end
    end
  end

  defp plan(context, opts, tools) do
    check = [base: opts[:base], fix: Keyword.get(opts, :fix, false), workspace: opts[:workspace]]

    for step <- steps(NativeCheck.kinds(context), opts) do
      fun =
        case step do
          "clang-format" -> fn -> NativeCheck.format(context, [tool: tools[step]] ++ check) end
          "rustfmt" -> fn -> NativeCheck.rust(context, :fmt, check) end
          "clippy" -> fn -> NativeCheck.rust(context, :clippy, check) end
          "clang-tidy" -> fn -> NativeCheck.tidy(context, [tool: tools[step]] ++ check) end
        end

      {step, fun}
    end
  end
end
