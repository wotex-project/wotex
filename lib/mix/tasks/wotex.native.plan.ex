defmodule Mix.Tasks.Wotex.Native.Plan do
  @shortdoc "Plans bounded native artifact qualification cells"

  @moduledoc """
  Refines the existing affected-package graph into the closed native matrix:

      mix wotex.native.plan [--base REF] [--package NAME] [--json | --count]
      mix wotex.native.plan --all [--limit CELLS]
  """

  use Mix.Task

  alias Wotex.Workspace.Affected
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Inventory
  alias Wotex.Workspace.NativeArtifact.Planner

  @switches [
    base: :string,
    package: :keep,
    all: :boolean,
    json: :boolean,
    count: :boolean,
    limit: :integer
  ]

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()

    with {:ok, descriptors} <- Inventory.load(manifest),
         {:ok, paths, planner_opts} <- changes(opts),
         :ok <- validate_packages(Keyword.get_values(opts, :package), manifest),
         {:ok, plan} <-
           Planner.plan(descriptors, manifest, paths,
             all: opts[:all] || false,
             packages: Keyword.get_values(opts, :package),
             fallback: planner_opts[:fallback] || false,
             fallback_reason: planner_opts[:fallback_reason],
             limit: opts[:limit] || manifest.native_artifact.matrix_limit
           ) do
      Mix.shell().info(render(plan, opts))
      :ok
    else
      {:error, errors} when is_list(errors) -> CLI.fail(Enum.join(errors, "\n"))
      {:error, message} -> CLI.fail(message)
    end
  end

  @doc "Parses planning options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)
    if opts[:json] && opts[:count], do: Mix.raise("--json and --count are mutually exclusive")
    opts
  end

  @doc "Renders a deterministic plan as human text, canonical JSON or a count."
  @spec render(Planner.plan(), keyword()) :: String.t()
  def render(plan, opts) do
    cond do
      opts[:count] -> Integer.to_string(length(plan.cells))
      opts[:json] -> CanonicalJSON.encode!(json_plan(plan))
      true -> human_plan(plan)
    end
  end

  defp changes(opts) do
    if (opts[:all] || false) or Keyword.get_values(opts, :package) != [] do
      {:ok, [], []}
    else
      case Affected.changed_paths(opts[:base]) do
        {:ok, paths} -> {:ok, paths, []}
        {:error, message} -> {:ok, [], [fallback: true, fallback_reason: message]}
      end
    end
  end

  defp validate_packages(packages, manifest) do
    case Enum.reject(packages, &Manifest.package?(&1, manifest)) do
      [] -> :ok
      unknown -> {:error, "unknown packages: #{Enum.join(unknown, ", ")}"}
    end
  end

  defp json_plan(plan) do
    %{
      "schema" => "wotex.native-plan@1",
      "fallback" => plan.fallback,
      "fallback_reason" => plan.fallback_reason,
      "count" => length(plan.cells),
      "cells" => Enum.map(plan.cells, &json_cell/1),
      "slices" => Enum.map(plan.slices, fn cells -> Enum.map(cells, &json_cell/1) end)
    }
  end

  defp json_cell(cell) do
    %{
      "package" => cell.package,
      "profile" => cell.profile,
      "target" => cell.target,
      "toolchain" => cell.toolchain,
      "system" => cell.system,
      "status" => Atom.to_string(cell.status),
      "reason" => cell.reason
    }
  end

  defp human_plan(plan) do
    prefix = if plan.fallback, do: "fallback: #{plan.fallback_reason}\n", else: ""

    rows =
      Enum.map_join(plan.cells, "\n", fn cell ->
        status =
          if cell.status == :unsupported, do: "unsupported: #{cell.reason}", else: "supported"

        "#{cell.package}/#{cell.profile}  #{cell.target}  #{cell.toolchain}  #{cell.system}  #{status}"
      end)

    prefix <> if(rows == "", do: "no native artifact cells", else: rows)
  end
end
