defmodule Mix.Tasks.Wotex.Test.Affected do
  @shortdoc "Runs the given test files, or the stale tests of the affected packages"

  @moduledoc """
  Runs tests from the repository root. The root alias is `mix
  test.affected`.

      mix wotex.test.affected [FILES...]
      mix wotex.test.affected [--base REF] [--package NAME]...

    * With `FILES` (repository-relative, optionally `:LINE`, e.g.
      `packages/wotex-coap/test/wotex/coap/codec_test.exs:42`), each file
      runs in its package: `mix test FILES...` per package.
    * Otherwise `mix test --stale` runs in every affected package (changed
      packages and their dependents), or in the `--package` selection.

  Every package runs with `WOTEX_PATH_DEPS=1`; a summary table follows and
  the task fails when any run failed.
  """

  use Mix.Task

  alias Wotex.Workspace
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.References
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Steps

  @switches [base: :string, package: :keep]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, files} = parse_args(args)
    manifest = Manifest.load!()
    targets = if files == [], do: stale_targets(manifest, opts), else: file_targets(manifest, files)

    if targets == [], do: Mix.shell().info("no affected packages")
    {rows, failed?} = Steps.run(targets, halt: false)
    Mix.shell().info("\n" <> Report.table(rows, [:package, :gate, :result, :seconds]))
    if failed?, do: CLI.fail("tests failed")
    :ok
  end

  @doc "Parses the options and the file arguments."
  @spec parse_args([String.t()]) :: {keyword(), [String.t()]}
  def parse_args(args) do
    {opts, files} = CLI.parse(args, @switches)

    if files != [] and opts != [],
      do: Mix.raise("give FILES or --base/--package, not both")

    {opts, files}
  end

  @doc """
  Groups repository-relative files (optionally `path:LINE`) by package, in
  the manifest's order, as package-relative paths.
  """
  @spec group_files([String.t()], Manifest.t(), Path.t()) ::
          {:ok, [{String.t(), [String.t()]}]} | {:error, String.t()}
  def group_files(files, %Manifest{} = manifest, root \\ Workspace.root()) do
    split =
      Enum.map(files, fn file ->
        {path, line} = split_line(file)

        case References.split_package(Workspace.relative(path, root)) do
          {name, inside} when is_binary(name) ->
            if Manifest.package?(name, manifest),
              do: {:ok, name, inside <> line},
              else: {:error, file}

          {nil, _} ->
            {:error, file}
        end
      end)

    case for {:error, file} <- split, do: file do
      [] ->
        groups = Enum.group_by(split, &elem(&1, 1), &elem(&1, 2))
        {:ok, for(name <- manifest.order, Map.has_key?(groups, name), do: {name, groups[name]})}

      outside ->
        {:error, "not inside a package directory: #{Enum.join(outside, ", ")}"}
    end
  end

  defp stale_targets(manifest, opts) do
    manifest
    |> CLI.classify!(opts)
    |> Enum.map(fn {name, mark} ->
      step = {"test --stale", ["test", "--stale"], [mix_env: "test"]}
      Steps.target(name, manifest, [step], %{gate: "stale (#{mark})"})
    end)
  end

  defp file_targets(manifest, files) do
    case group_files(files, manifest) do
      {:ok, groups} ->
        Enum.map(groups, fn {name, package_files} ->
          step = {"test", ["test" | package_files], [mix_env: "test"]}
          Steps.target(name, manifest, [step], %{gate: "files"})
        end)

      {:error, message} ->
        CLI.fail(message)
    end
  end

  defp split_line(file) do
    case Regex.run(~r/^(.*?)((?::\d+)+)$/, file) do
      [_, path, line] -> {path, line}
      nil -> {file, ""}
    end
  end
end
