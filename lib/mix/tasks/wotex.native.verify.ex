defmodule Mix.Tasks.Wotex.Native.Verify do
  @shortdoc "Verifies one local native artifact without adopting it"

  @moduledoc """
  Verifies one archive against the current admitted descriptor and target:

      mix wotex.native.verify --package NAME --profile PROFILE --target TARGET \
        --artifact /absolute/artifact.tar [--json]

  The operation is read-only. It performs no extraction, cache adoption,
  retrieval, build, publication or application start.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Identity
  alias Wotex.Workspace.NativeArtifact.Inventory
  alias Wotex.Workspace.NativeArtifact.Verifier

  @switches [
    package: :string,
    profile: :string,
    target: :string,
    artifact: :string,
    revision: :string,
    json: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()

    with {:ok, descriptors} <- Inventory.load(manifest),
         {:ok, descriptor} <- Inventory.fetch(descriptors, opts[:package], opts[:profile]),
         {:ok, revision} <- revision(opts[:revision]),
         {:ok, identity} <- Identity.build(descriptor, opts[:target], revision, manifest),
         {:ok, result} <-
           Verifier.verify(
             opts[:artifact],
             descriptor,
             opts[:target],
             identity.identity
           ) do
      Mix.shell().info(render(result, opts[:json] || false))
      :ok
    else
      {:error, errors} when is_list(errors) -> CLI.fail(Enum.join(errors, "\n"))
      {:error, message} -> CLI.fail(message)
    end
  end

  @doc "Parses the one-cell verification command."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    for key <- ~w(package profile target artifact)a do
      if opts[key] in [nil, ""], do: Mix.raise("--#{key} is required")
    end

    if Path.type(opts[:artifact]) != :absolute, do: Mix.raise("--artifact must be absolute")
    opts
  end

  defp revision(nil), do: Identity.repository_revision()
  defp revision(value), do: {:ok, value}

  defp render(result, true) do
    CanonicalJSON.encode!(%{
      "schema" => "wotex.native-verification@1",
      "package" => result.manifest.package,
      "profile" => result.manifest.profile,
      "target" => result.manifest.target,
      "build_identity" => result.manifest.build_identity,
      "payload_identity" => result.manifest.payload_identity,
      "transport_sha256" => result.transport_sha256,
      "entries" => length(result.manifest.entries),
      "compressed_size" => result.compressed_size,
      "expanded_size" => result.expanded_size,
      "result" => "passed",
      "state" => "built"
    })
  end

  defp render(result, false) do
    "verified #{result.manifest.package}/#{result.manifest.profile} #{result.manifest.target}  " <>
      "payload #{result.manifest.payload_identity}  #{length(result.manifest.entries)} entries"
  end
end
