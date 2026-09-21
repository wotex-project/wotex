defmodule Mix.Tasks.Wotex.Native.Adopt do
  @shortdoc "Verifies and atomically adopts one local native artifact"

  @moduledoc """
  Verifies one local archive and installs it in the exact local cache cell:

      mix wotex.native.adopt --package NAME --profile PROFILE --target TARGET \
        --artifact /absolute/artifact.tar --cache /absolute/cache [--json]

  The operation performs no retrieval, build, publication or application
  start. An existing cache entry is reused only after complete revalidation.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.Cache
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Identity
  alias Wotex.Workspace.NativeArtifact.Inventory

  @switches [
    package: :string,
    profile: :string,
    target: :string,
    artifact: :string,
    cache: :string,
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
         {:ok, entry} <-
           Cache.adopt(
             opts[:artifact],
             descriptor,
             opts[:target],
             identity.identity,
             opts[:cache]
           ) do
      Mix.shell().info(render(entry, opts[:json] || false))
      :ok
    else
      {:error, errors} when is_list(errors) -> CLI.fail(Enum.join(errors, "\n"))
      {:error, message} -> CLI.fail(message)
    end
  end

  @doc "Parses the one-cell local adoption command."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    for key <- ~w(package profile target artifact cache)a do
      if opts[key] in [nil, ""], do: Mix.raise("--#{key} is required")
    end

    for key <- ~w(artifact cache)a do
      if Path.type(opts[key]) != :absolute, do: Mix.raise("--#{key} must be absolute")
    end

    opts
  end

  defp revision(nil), do: Identity.repository_revision()
  defp revision(value), do: {:ok, value}

  defp render(entry, true) do
    CanonicalJSON.encode!(%{
      "schema" => "wotex.native-cache-adoption@1",
      "package" => entry.manifest.package,
      "profile" => entry.manifest.profile,
      "target" => entry.manifest.target,
      "build_identity" => entry.manifest.build_identity,
      "payload_identity" => entry.manifest.payload_identity,
      "transport_sha256" => entry.transport_sha256,
      "transport_size" => entry.transport_size,
      "entries" => length(entry.manifest.entries),
      "cache_path" => entry.path,
      "reused" => entry.reused,
      "result" => "installed"
    })
  end

  defp render(entry, false) do
    disposition = if entry.reused, do: "reused", else: "installed"

    "#{disposition} #{entry.manifest.package}/#{entry.manifest.profile} " <>
      "#{entry.manifest.target}  #{entry.manifest.build_identity}"
  end
end
