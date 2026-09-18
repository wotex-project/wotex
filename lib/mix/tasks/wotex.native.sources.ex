defmodule Mix.Tasks.Wotex.Native.Sources do
  @shortdoc "Lists pinned native sources and verifies local digests"

  @moduledoc """
  For every native package, reads its pinned-source manifest when it has a
  known shape (see `Wotex.Workspace.Native`), lists the upstream pins and
  verifies the sha256 digest of every pinned file present locally.

      mix wotex.native.sources

  A package without a manifest of a known shape is reported as
  `no manifest`. The task fails on a digest mismatch or an unreadable
  manifest. The root alias is `mix native.sources`.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Native

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    parse_args(args)
    reports = Native.sources()
    Enum.each(reports, &print/1)
    unless Native.sources_ok?(reports), do: CLI.fail("native source verification failed")
    :ok
  end

  @doc "Parses the task's options (it takes none)."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, [])
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")
    opts
  end

  defp print(%{status: :no_manifest} = report) do
    Mix.shell().info("#{report.package}: no manifest")
  end

  defp print(report) do
    Mix.shell().info(
      "#{report.package}: #{report.status} (#{Enum.join(report.manifests, ", ")}; " <>
        "#{length(report.pins)} pin(s), #{length(report.verified)} file(s) verified, " <>
        "#{length(report.absent)} absent locally)"
    )

    Enum.each(report.pins, fn pin ->
      Mix.shell().info("  #{pin.name} #{pin.version || "-"} #{pin.commit || "-"}")
    end)

    Enum.each(report.problems, &Mix.shell().error("  " <> &1))
  end
end
