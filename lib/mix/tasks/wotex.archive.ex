defmodule Mix.Tasks.Wotex.Archive do
  @shortdoc "Builds and checks the Hex archive of the selected packages"

  @moduledoc """
  Builds each selected package's Hex archive the way a release would, then
  runs the package's own archive check.

      mix wotex.archive [--all] [--package NAME]... [--base REF]

  For every package, in topological order:

    1. `mix package` if the package's `mix.exs` defines a `package` alias,
       else `mix hex.build`, with `WOTEX_PATH_DEPS` unset and `MIX_ENV=dev`;
    2. `mix run --no-start bin/check_archive.exs` (or `bin/check_package.exs`)
       with `WOTEX_PATH_DEPS=1`, when the script exists;
    3. generated `*.tar` files in the package directory are removed.

  A summary table follows; the task fails on the first failing package.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Runner

  @switches CLI.selection_switches()
  @scripts ["bin/check_archive.exs", "bin/check_package.exs"]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()
    names = CLI.select!(manifest, opts)
    if names == [], do: Mix.shell().info("no affected packages")

    {rows, failed?} =
      Enum.reduce_while(names, {[], false}, fn name, {rows, _failed?} ->
        path = Manifest.absolute_path(name, manifest)
        {result, seconds} = CLI.timed(fn -> archive(path) end)
        rows = [%{package: name, result: result, seconds: seconds} | rows]
        if result == "ok", do: {:cont, {rows, false}}, else: {:halt, {rows, true}}
      end)

    Mix.shell().info("\n" <> Report.table(Enum.reverse(rows)))
    if failed?, do: CLI.fail("archive check failed")
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, @switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")
    opts
  end

  @doc """
  Whether a `mix.exs` text defines a `package` alias (as opposed to the
  `package:` project key, whose value is a function call).
  """
  @spec package_alias?(String.t()) :: boolean()
  def package_alias?(mix_exs) do
    Regex.match?(~r/(?:^|[\[,\s])"?package"?:\s*["\[]/m, mix_exs)
  end

  @doc "The archive check script of a package directory, if any."
  @spec check_script(Path.t()) :: String.t() | nil
  def check_script(path), do: Enum.find(@scripts, &File.regular?(Path.join(path, &1)))

  defp archive(path) do
    build =
      if package_alias?(File.read!(Path.join(path, "mix.exs"))),
        do: ["package"],
        else: ["hex.build"]

    result =
      with 0 <- Runner.run(path, build, path_deps: false, mix_env: "dev"),
           :ok <- check(path) do
        "ok"
      else
        status when is_integer(status) -> "#{hd(build)} failed (#{status})"
        {:error, message} -> message
      end

    path
    |> Path.join("*.tar")
    |> Path.wildcard()
    |> Enum.each(&File.rm/1)

    result
  end

  defp check(path) do
    case check_script(path) do
      nil ->
        :ok

      script ->
        case Runner.run(path, ["run", "--no-start", script], path_deps: true) do
          0 -> :ok
          status -> {:error, "#{script} failed (#{status})"}
        end
    end
  end
end
