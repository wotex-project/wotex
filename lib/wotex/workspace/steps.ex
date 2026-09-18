defmodule Wotex.Workspace.Steps do
  @moduledoc """
  Runs sequences of Mix commands in package directories and collects one
  summary row per target.

  A target is a directory with an ordered list of steps. Each step runs
  through `Wotex.Workspace.Runner` (a separate OS process); a target stops
  at its first failing step and its result names that step. With `halt:
  true` (the default) the remaining targets are skipped after a failure;
  with `halt: false` every target runs and the failure is reported at the
  end.

  The gates live here too: `full_gate/1` is the package's own `mix check`
  and `fast_gate/0` the inner-loop subset.
  """

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Runner

  @typedoc "A label, the Mix arguments and the `Wotex.Workspace.Runner` options."
  @type step :: {String.t(), [String.t()], [Runner.option()]}

  @typedoc """
  A directory and its steps. Every other key (`:package`, `:gate`, `:step`)
  is copied into the summary row.
  """
  @type target :: %{
          required(:path) => Path.t(),
          required(:steps) => [step()],
          optional(atom()) => String.t()
        }

  @typedoc "Runs `mix args` in a directory and returns the exit status."
  @type runner :: (Path.t(), [String.t()], [Runner.option()] -> non_neg_integer())

  @type option :: {:halt, boolean()} | {:runner, runner()}

  @doc """
  The full gate of a package: `mix deps.get --check-locked` and `mix check
  --no-retry`, passing `--except TOOL` for every skipped tool.
  """
  @spec full_gate([String.t()]) :: [step()]
  def full_gate(skip \\ []) do
    except = Enum.flat_map(skip, &["--except", &1])

    [
      {"deps.get", ["deps.get", "--check-locked"], []},
      {"check", ["check", "--no-retry" | except], []}
    ]
  end

  @doc """
  The inner-loop gate of a package, in `MIX_ENV=test` so that compilation
  is shared with the test run: compile with warnings as errors, format
  check, `credo --strict` and `mix test`.
  """
  @spec fast_gate() :: [step()]
  def fast_gate do
    env = [mix_env: "test"]

    [
      {"compile", ["compile", "--warnings-as-errors"], env},
      {"format", ["format", "--check-formatted"], env},
      {"credo", ["credo", "--strict"], env},
      {"test", ["test"], env}
    ]
  end

  @doc "A target for package `name`; `fields` are merged into its row."
  @spec target(String.t(), Manifest.t(), [step()], map()) :: target()
  def target(name, %Manifest{} = manifest, steps, fields \\ %{}) do
    Map.merge(%{package: name, path: Manifest.absolute_path(name, manifest), steps: steps}, fields)
  end

  @doc """
  Runs every target and returns the summary rows and whether any target
  failed.
  """
  @spec run([target()], [option()]) :: {[Report.row()], boolean()}
  def run(targets, opts \\ []) do
    halt? = Keyword.get(opts, :halt, true)
    runner = Keyword.get(opts, :runner, &Runner.run/3)

    {rows, failed?} =
      Enum.reduce_while(targets, {[], false}, fn target, {rows, failed?} ->
        {result, seconds} = CLI.timed(fn -> run_steps(target.path, target.steps, runner) end)
        row = Map.merge(Map.drop(target, [:path, :steps]), %{result: result, seconds: seconds})
        failure? = result != "ok"
        acc = {[row | rows], failed? or failure?}
        if failure? and halt?, do: {:halt, acc}, else: {:cont, acc}
      end)

    {Enum.reverse(rows), failed?}
  end

  @doc """
  Runs `steps` in `path` until one fails. Returns `"ok"` or
  `"<label> failed (<status>)"`.
  """
  @spec run_steps(Path.t(), [step()], runner()) :: String.t()
  def run_steps(path, steps, runner \\ &Runner.run/3) do
    Enum.reduce_while(steps, "ok", fn {label, args, runner_opts}, _acc ->
      case runner.(path, args, runner_opts) do
        0 -> {:cont, "ok"}
        status -> {:halt, "#{label} failed (#{status})"}
      end
    end)
  end
end
