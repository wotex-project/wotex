defmodule Mix.Tasks.Wotex.Native.Manifest do
  @shortdoc "Builds one deterministic native payload manifest"

  @moduledoc """
  Hashes descriptor-declared outputs in an existing absolute payload root:

      mix wotex.native.manifest --package NAME --profile PROFILE --target TARGET \
        --root /absolute/payload --output /absolute/artifact-manifest.json

  The command performs no build, download, cache adoption or application start.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.Identity
  alias Wotex.Workspace.NativeArtifact.Inventory
  alias Wotex.Workspace.NativeArtifact.PayloadManifest

  @switches [
    package: :string,
    profile: :string,
    target: :string,
    root: :string,
    output: :string,
    revision: :string
  ]

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)
    inventory = Manifest.load!()

    with {:ok, descriptors} <- Inventory.load(inventory),
         {:ok, descriptor} <- Inventory.fetch(descriptors, opts[:package], opts[:profile]),
         {:ok, revision} <- revision(opts[:revision]),
         {:ok, identity} <- Identity.build(descriptor, opts[:target], revision, inventory),
         {:ok, manifest} <-
           PayloadManifest.build(descriptor, opts[:target], identity.identity, opts[:root]),
         {:ok, bytes} <- PayloadManifest.encode(manifest),
         :ok <- write_new(opts[:output], bytes <> "\n") do
      Mix.shell().info("wrote #{opts[:output]}  #{manifest.payload_identity}")
      :ok
    else
      {:error, errors} when is_list(errors) -> CLI.fail(Enum.join(errors, "\n"))
      {:error, message} -> CLI.fail(message)
    end
  end

  @doc "Parses the one-cell manifest command."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    for key <- ~w(package profile target root output)a do
      if opts[key] in [nil, ""], do: Mix.raise("--#{key} is required")
    end

    for key <- ~w(root output)a do
      if Path.type(opts[key]) != :absolute, do: Mix.raise("--#{key} must be absolute")
    end

    opts
  end

  defp revision(nil), do: Identity.repository_revision()
  defp revision(value), do: {:ok, value}

  defp write_new(path, bytes) do
    temporary = path <> ".tmp-#{System.unique_integer([:positive, :monotonic])}"

    if File.exists?(path) do
      {:error, "output already exists: #{path}"}
    else
      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- write_exclusive(temporary, bytes),
           :ok <- File.rename(temporary, path) do
        :ok
      else
        {:error, reason} when is_atom(reason) ->
          File.rm(temporary)
          {:error, "cannot write #{path}: #{:file.format_error(reason)}"}

        {:error, _} = error ->
          File.rm(temporary)
          error
      end
    end
  end

  defp write_exclusive(path, bytes) do
    case File.open(path, [:write, :binary, :exclusive]) do
      {:ok, io} ->
        try do
          IO.binwrite(io, bytes)
        after
          File.close(io)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
