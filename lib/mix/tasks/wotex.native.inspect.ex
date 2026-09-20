defmodule Mix.Tasks.Wotex.Native.Inspect do
  @shortdoc "Inspects admitted native artifact descriptors and identities"

  @moduledoc """
  Reads the closed native artifact inventory without compiling package apps:

      mix wotex.native.inspect --package NAME [--profile PROFILE]
      mix wotex.native.inspect --package NAME --profile PROFILE --target TARGET --identity
      mix wotex.native.inspect --all --json
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Identity
  alias Wotex.Workspace.NativeArtifact.Inventory

  @switches [
    package: :string,
    profile: :string,
    target: :string,
    identity: :boolean,
    revision: :string,
    all: :boolean,
    json: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()

    with {:ok, descriptors} <- Inventory.load(manifest),
         {:ok, selected} <- select(descriptors, opts),
         {:ok, result} <- inspect_selected(selected, manifest, opts) do
      output = if opts[:json], do: CanonicalJSON.encode!(result), else: render(result)
      Mix.shell().info(output)
      :ok
    else
      {:error, errors} when is_list(errors) -> CLI.fail(Enum.join(errors, "\n"))
      {:error, message} -> CLI.fail(message)
    end
  end

  @doc "Parses and validates inspection options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    cond do
      opts[:all] && opts[:package] ->
        Mix.raise("--all and --package are mutually exclusive")

      not (opts[:all] || false) and opts[:package] in [nil, ""] ->
        Mix.raise("--package NAME is required unless --all is used")

      opts[:target] && is_nil(opts[:profile]) ->
        Mix.raise("--target requires --profile")

      opts[:identity] && (is_nil(opts[:profile]) or is_nil(opts[:target])) ->
        Mix.raise("--identity requires --profile and --target")

      true ->
        opts
    end
  end

  @doc "Renders inspection records in stable human-readable form."
  @spec render([map()]) :: String.t()
  def render(records) do
    Enum.map_join(records, "\n", fn record ->
      support =
        record["targets"]
        |> Enum.map_join(", ", fn target ->
          suffix =
            if target["status"] == "unsupported",
              do: " (unsupported: #{target["reason"]})",
              else: ""

          target["name"] <> suffix
        end)

      identity = if record["build_identity"], do: "  #{record["build_identity"]}", else: ""
      "#{record["package"]}/#{record["profile"]}  #{record["kind"]}  #{support}#{identity}"
    end)
  end

  defp select(descriptors, opts) do
    selected =
      Enum.filter(descriptors, fn descriptor ->
        ((opts[:all] || false) or descriptor.package == opts[:package]) and
          (is_nil(opts[:profile]) or descriptor.profile == opts[:profile])
      end)

    if selected == [],
      do: {:error, "no admitted native artifact descriptor matches the selection"},
      else: {:ok, selected}
  end

  defp inspect_selected(descriptors, manifest, opts) do
    revision = opts[:revision]

    with {:ok, revision} <- resolve_revision(revision, opts[:identity] || false) do
      result =
        Enum.reduce_while(descriptors, {:ok, []}, fn descriptor, {:ok, records} ->
          case record(descriptor, manifest, opts, revision) do
            {:ok, record} -> {:cont, {:ok, [record | records]}}
            {:error, _} = error -> {:halt, error}
          end
        end)

      case result do
        {:ok, records} -> {:ok, Enum.reverse(records)}
        {:error, _} = error -> error
      end
    end
  end

  defp record(descriptor, manifest, opts, revision) do
    targets =
      descriptor.targets
      |> Enum.filter(&(is_nil(opts[:target]) or &1.name == opts[:target]))
      |> Enum.map(
        &%{"name" => &1.name, "status" => Atom.to_string(&1.status), "reason" => &1.reason}
      )

    cond do
      targets == [] ->
        {:error,
         "target #{inspect(opts[:target])} is not declared by #{descriptor.package}/#{descriptor.profile}"}

      opts[:identity] ->
        with {:ok, result} <- Identity.build(descriptor, opts[:target], revision, manifest) do
          {:ok,
           base_record(descriptor, targets)
           |> Map.put("build_identity", result.identity)
           |> Map.put("identity_document", result.document)}
        end

      true ->
        {:ok, base_record(descriptor, targets)}
    end
  end

  defp base_record(descriptor, targets) do
    %{
      "package" => descriptor.package,
      "profile" => descriptor.profile,
      "kind" => descriptor.kind,
      "descriptor" => descriptor.path,
      "targets" => targets,
      "build_identity" => nil
    }
  end

  defp resolve_revision(nil, true), do: Identity.repository_revision()
  defp resolve_revision(revision, true), do: {:ok, revision}
  defp resolve_revision(_, false), do: {:ok, nil}
end
