defmodule Mix.Tasks.Wotex.Native.Advisories do
  @shortdoc "Queries OSV for advisories against pinned native sources"

  @moduledoc """
  Queries the OSV database (`https://api.osv.dev/v1/query`) for every
  pinned upstream source of the native packages, by commit when one is
  pinned, else by name and version.

      mix wotex.native.advisories [--package NAME] [--offline]

  `--package` may be repeated to query only those packages' pins. Without
  it, every native package and the repository's tooling pins are queried.
  `--offline` performs no query and succeeds. The task fails on any
  unreviewed advisory or failed query. Exact source-bound accepted exceptions
  remain in the result and manifest but are muted in the console report.
  The root alias is `mix native.advisories`.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Native

  @switches [offline: :boolean, package: :keep]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    names = Keyword.get_values(opts, :package)

    reports =
      Enum.filter(Native.sources(), fn report -> names == [] or report.package in names end)

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

    native =
      Manifest.load!()
      |> Manifest.native_packages()
      |> Enum.map(& &1.name)

    for name <- Keyword.get_values(opts, :package) do
      unless name in native, do: Mix.raise("not a native package: #{inspect(name)}")
    end

    opts
  end

  defp print(%{pin: pin, result: {:ok, []}}),
    do: Mix.shell().info("#{describe(pin)}: no advisories")

  defp print(%{pin: pin, result: {:ok, vulnerabilities}}) do
    blocking = Enum.reject(vulnerabilities, &Map.has_key?(&1, :review))

    if blocking == [] do
      Mix.shell().info("#{describe(pin)}: no blocking advisories")
    else
      Mix.shell().error("#{describe(pin)}: #{length(blocking)} advisory(ies)")
      Enum.each(blocking, &Mix.shell().error("  #{&1.id} #{&1.summary}"))
    end
  end

  defp print(%{pin: pin, result: {:error, message}}),
    do: Mix.shell().error("#{describe(pin)}: #{message}")

  defp describe(pin), do: "#{pin.name} #{pin.version || "-"} #{pin.commit || "-"} (#{pin.manifest})"
end
