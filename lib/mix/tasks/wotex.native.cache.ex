defmodule Mix.Tasks.Wotex.Native.Cache do
  @shortdoc "Inspects, deletes or garbage-collects the local native cache"

  @moduledoc """
  Inspects or deletes one exact cache identity, or runs bounded collection:

      mix wotex.native.cache --cache /absolute/cache --identity SHA256 \
        --package NAME --profile PROFILE --target TARGET [--json]
      mix wotex.native.cache --cache /absolute/cache --identity SHA256 --delete
      mix wotex.native.cache --cache /absolute/cache --gc \
        [--keep SHA256] [--max-scan N] [--max-remove N]

  Inspection revalidates the current descriptor, target, manifest, extracted
  payload and cached transport. Deletion and collection never follow symlinks.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.Cache
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Inventory

  @digest ~r/^[0-9a-f]{64}$/
  @switches [
    cache: :string,
    identity: :string,
    package: :string,
    profile: :string,
    target: :string,
    delete: :boolean,
    gc: :boolean,
    keep: :keep,
    max_scan: :integer,
    max_remove: :integer,
    json: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)

    case action(opts) do
      :inspect -> inspect_entry(opts)
      :delete -> delete_entry(opts)
      :gc -> collect(opts)
    end
  end

  @doc "Parses one exact cache operation or one explicitly bounded collection."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    if opts[:cache] in [nil, ""], do: Mix.raise("--cache is required")
    if Path.type(opts[:cache]) != :absolute, do: Mix.raise("--cache must be absolute")
    if opts[:delete] && opts[:gc], do: Mix.raise("--delete and --gc are mutually exclusive")

    validate_selection(opts)
    opts
  end

  defp validate_selection(opts) do
    if opts[:gc] do
      validate_gc(opts)
    else
      validate_identity(opts[:identity])
      validate_exact_action(opts)
    end
  end

  defp validate_gc(opts) do
    if opts[:identity], do: Mix.raise("--gc does not accept --identity")

    if Enum.any?(~w(package profile target)a, &opts[&1]) do
      Mix.raise("--gc does not accept a package, profile or target")
    end

    for identity <- Keyword.get_values(opts, :keep), do: validate_identity(identity)
  end

  defp validate_exact_action(opts) do
    if Keyword.get_values(opts, :keep) != [], do: Mix.raise("--keep requires --gc")
    if opts[:max_scan] || opts[:max_remove], do: Mix.raise("collection bounds require --gc")

    unless opts[:delete] do
      for key <- ~w(package profile target)a do
        if opts[key] in [nil, ""], do: Mix.raise("--#{key} is required for inspection")
      end
    end
  end

  defp validate_identity(identity) do
    unless is_binary(identity) and Regex.match?(@digest, identity) do
      Mix.raise("--identity and --keep values must be full lowercase SHA-256 digests")
    end
  end

  defp action(opts) do
    cond do
      opts[:gc] -> :gc
      opts[:delete] -> :delete
      true -> :inspect
    end
  end

  defp inspect_entry(opts) do
    manifest = Manifest.load!()

    with {:ok, descriptors} <- Inventory.load(manifest),
         {:ok, descriptor} <- Inventory.fetch(descriptors, opts[:package], opts[:profile]),
         {:ok, entry} <- Cache.inspect(opts[:cache], opts[:identity], descriptor, opts[:target]) do
      output = if opts[:json], do: encode_entry(entry), else: render_entry(entry)
      Mix.shell().info(output)
      :ok
    else
      {:error, errors} when is_list(errors) -> CLI.fail(Enum.join(errors, "\n"))
      {:error, message} -> CLI.fail(message)
    end
  end

  defp delete_entry(opts) do
    case Cache.delete(opts[:cache], opts[:identity]) do
      :ok ->
        output =
          if opts[:json] do
            CanonicalJSON.encode!(%{
              "schema" => "wotex.native-cache-operation@1",
              "action" => "delete",
              "build_identity" => opts[:identity],
              "result" => "removed"
            })
          else
            "removed #{opts[:identity]}"
          end

        Mix.shell().info(output)
        :ok

      {:error, message} ->
        CLI.fail(message)
    end
  end

  defp collect(opts) do
    cache_opts = [
      keep: Keyword.get_values(opts, :keep),
      max_scan: opts[:max_scan] || 256,
      max_remove: opts[:max_remove] || 32
    ]

    case Cache.garbage_collect(opts[:cache], cache_opts) do
      {:ok, result} ->
        output = if opts[:json], do: encode_collection(result), else: render_collection(result)
        Mix.shell().info(output)
        :ok

      {:error, message} ->
        CLI.fail(message)
    end
  end

  defp encode_entry(entry) do
    CanonicalJSON.encode!(%{
      "schema" => "wotex.native-cache-entry-inspection@1",
      "package" => entry.manifest.package,
      "profile" => entry.manifest.profile,
      "target" => entry.manifest.target,
      "build_identity" => entry.manifest.build_identity,
      "payload_identity" => entry.manifest.payload_identity,
      "transport_sha256" => entry.transport_sha256,
      "transport_size" => entry.transport_size,
      "entries" => length(entry.manifest.entries),
      "cache_path" => entry.path,
      "result" => "valid"
    })
  end

  defp render_entry(entry) do
    "valid #{entry.manifest.package}/#{entry.manifest.profile} #{entry.manifest.target}  " <>
      "#{entry.manifest.build_identity}  #{length(entry.manifest.entries)} entries"
  end

  defp encode_collection(result) do
    CanonicalJSON.encode!(%{
      "schema" => "wotex.native-cache-collection@1",
      "scanned" => result.scanned,
      "removed" => result.removed,
      "retained" => result.retained,
      "skipped" => result.skipped
    })
  end

  defp render_collection(result) do
    "scanned #{result.scanned}  removed #{length(result.removed)}  " <>
      "retained #{length(result.retained)}  skipped #{length(result.skipped)}"
  end
end
