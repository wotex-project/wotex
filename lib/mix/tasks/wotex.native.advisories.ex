defmodule Mix.Tasks.Wotex.Native.Advisories do
  @shortdoc "Queries OSV for advisories against pinned native sources"

  @moduledoc """
  Queries the OSV database (`https://api.osv.dev/v1/query`) for every
  pinned upstream source of the native packages, by commit when one is
  pinned, else by name and version.

      mix wotex.native.advisories [--offline]

  `--offline` performs no query and succeeds. The task fails on any
  advisory or failed query.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Native

  @switches [offline: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    reports = Native.sources()
    pins = Native.pins(reports)

    if opts[:offline] do
      Mix.shell().info("offline: skipped #{length(pins)} OSV query(ies)")
      Enum.each(pins, &Mix.shell().info("  #{describe(&1)}"))
    else
      results = Native.advisories(reports)
      Enum.each(results, &print/1)
      unless Native.advisories_clean?(results), do: CLI.fail("advisory check failed")
    end

    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, @switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")
    opts
  end

  defp print(%{pin: pin, result: {:ok, []}}),
    do: Mix.shell().info("#{describe(pin)}: no advisories")

  defp print(%{pin: pin, result: {:ok, vulnerabilities}}) do
    Mix.shell().error("#{describe(pin)}: #{length(vulnerabilities)} advisory(ies)")
    Enum.each(vulnerabilities, &Mix.shell().error("  #{&1.id} #{&1.summary}"))
  end

  defp print(%{pin: pin, result: {:error, message}}),
    do: Mix.shell().error("#{describe(pin)}: #{message}")

  defp describe(pin), do: "#{pin.name} #{pin.version || "-"} #{pin.commit || "-"} (#{pin.manifest})"
end
