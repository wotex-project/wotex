defmodule Mix.Tasks.Wotex.Boundary do
  @shortdoc "Checks that packages use only the public API of their siblings"

  @moduledoc """
  The sibling-API gate. For each selected package it compiles the package
  (`WOTEX_PATH_DEPS=1 MIX_ENV=test mix compile`), reads the docs chunks of
  the compiled sibling beams and reports every source reference to a
  sibling module with `@moduledoc false` or function with `@doc false`:

      packages/wotex-coap/lib/wotex/coap.ex:12: Wotex.Runtime.Internal.plan/2 is not public API

      mix wotex.boundary [--all] [--package NAME]... [--base REF]

  The default selection is the affected set. The task fails on any
  finding. See `Wotex.Workspace.Boundary` for what the analysis resolves
  and what it conservatively leaves alone.
  """

  use Mix.Task

  alias Wotex.Workspace.Boundary
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest

  @switches CLI.selection_switches()

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()
    names = CLI.select!(manifest, opts)
    if names == [], do: Mix.shell().info("no affected packages")

    failures =
      Enum.reduce(names, 0, fn name, failures ->
        case Boundary.run(name, manifest) do
          {:ok, []} ->
            Mix.shell().info("#{name}: no boundary findings")
            failures

          {:ok, findings} ->
            Enum.each(findings, &Mix.shell().error(Boundary.format(&1)))
            Mix.shell().error("#{name}: #{length(findings)} boundary finding(s)")
            failures + 1

          {:error, message} ->
            Mix.shell().error(message)
            failures + 1
        end
      end)

    if failures > 0, do: CLI.fail("boundary gate failed for #{failures} package(s)")
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, @switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")
    opts
  end
end
