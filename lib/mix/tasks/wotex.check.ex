defmodule Mix.Tasks.Wotex.Check do
  @shortdoc "Runs the gate of the affected packages"

  @moduledoc """
  Runs each selected package's gate, `mix deps.get --check-locked` followed
  by `mix check --no-retry`, with `WOTEX_PATH_DEPS=1`, in topological order,
  stopping at the first failure. A summary table follows.

      mix wotex.check [--all] [--package NAME]... [--base REF] [--lane minimum|current] [--env ENV]

    * default: the affected set (see `mix wotex.affected`);
    * `--all`: every package, announced as `running the gate of N packages`;
    * `--package NAME`: the named packages (repeatable);
    * `--base REF`: the comparison base for the affected set;
    * `--lane NAME`: prints the lane's toolchain, warns when the running
      Elixir differs (CI selects the toolchain) and passes `--except TOOL`
      for every tool the lane skips in `tooling/packages.yaml`. The minimum
      lane runs behaviour tools only; static analysis runs on the current
      lane;
    * `--env ENV`: export `MIX_ENV=ENV` to the gate commands.

  Never run `--all` for a one-package change; see the root `CLAUDE.md`.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Runner

  @switches CLI.selection_switches() ++ [lane: :string, env: :string]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()
    names = CLI.select!(manifest, opts)
    skip = report_lane(opts[:lane], manifest)

    cond do
      opts[:all] -> Mix.shell().info("running the gate of #{length(names)} packages")
      names == [] -> Mix.shell().info("no affected packages")
      true -> Mix.shell().info("running the gate of #{Enum.join(names, ", ")}")
    end

    {rows, failed?} = run_gates(names, manifest, opts[:env], skip)
    Mix.shell().info("\n" <> Report.table(rows))
    if failed?, do: CLI.fail("gate failed")
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, @switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

    if opts[:lane] && opts[:lane] not in ["minimum", "current"],
      do: Mix.raise("--lane must be minimum or current")

    opts
  end

  @doc "The gate commands for one package, skipping the given `mix check` tools."
  @spec commands([String.t()]) :: [{String.t(), [String.t()]}]
  def commands(skip \\ []) do
    except = Enum.flat_map(skip, &["--except", &1])
    [{"deps.get", ["deps.get", "--check-locked"]}, {"check", ["check", "--no-retry" | except]}]
  end

  @doc "Runs the gate commands of one package directory; `\"ok\"` on success."
  @spec gate(Path.t(), String.t() | nil, [String.t()]) :: String.t()
  def gate(path, env, skip \\ []) do
    runner_opts = if env, do: [mix_env: env], else: []

    Enum.reduce_while(
      commands(skip),
      "ok",
      fn {label, command}, _acc ->
        case Runner.run(path, command, runner_opts) do
          0 -> {:cont, "ok"}
          status -> {:halt, "#{label} failed (#{status})"}
        end
      end
    )
  end

  defp run_gates(names, manifest, env, skip) do
    {rows, failed?} =
      Enum.reduce_while(names, {[], false}, fn name, {rows, _failed?} ->
        path = Manifest.absolute_path(name, manifest)
        {result, seconds} = CLI.timed(fn -> gate(path, env, skip) end)
        rows = [%{package: name, result: result, seconds: seconds} | rows]
        if result == "ok", do: {:cont, {rows, false}}, else: {:halt, {rows, true}}
      end)

    {Enum.reverse(rows), failed?}
  end

  defp report_lane(nil, _manifest), do: []

  defp report_lane(name, manifest) do
    case Manifest.lane(name, manifest) do
      {:ok, %{elixir: elixir, otp: otp, skip: skip}} ->
        Mix.shell().info("lane #{name}: elixir #{elixir}, otp #{otp}")
        if skip != [], do: Mix.shell().info("lane #{name} skips: #{Enum.join(skip, ", ")}")
        [expected | _] = String.split(elixir, "-")

        if expected != System.version() do
          Mix.shell().error(
            "warning: running Elixir #{System.version()} on OTP #{System.otp_release()}; " <>
              "lane #{name} expects #{elixir}. CI selects the toolchain."
          )
        end

        skip

      :error ->
        CLI.fail("the manifest declares no lane #{inspect(name)}")
    end
  end
end
