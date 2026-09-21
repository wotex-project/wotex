defmodule Mix.Tasks.Wotex.Native.Retrieve do
  @shortdoc "Retrieves, verifies and adopts one exact prebuilt artifact"

  @moduledoc """
  Retrieves one explicitly admitted prebuilt object under bounded transport and
  archive limits:

      mix wotex.native.retrieve --package NAME --profile PROFILE --target TARGET \
        --identity FULL_SHA256 --sha256 FULL_TRANSPORT_SHA256 --cache /absolute/cache

  This command is the `prebuilt` delivery mode. It never builds from source on
  failure. `mix native.build` is the explicit source-only operation; callers
  that use `prefer_prebuilt` must separately enable source fallback for that
  invocation through the delivery policy module.

  `--source NAME` restricts the attempt to one descriptor-declared source.
  `--authorization-env NAME` reads a request authorization value without
  placing it in task output and requires that exact source selection.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Delivery
  alias Wotex.Workspace.NativeArtifact.Inventory
  alias Wotex.Workspace.NativeArtifact.Retrieval

  @digest ~r/^[0-9a-f]{64}$/
  @environment ~r/^[A-Z_][A-Z0-9_]*$/
  @switches [
    package: :string,
    profile: :string,
    target: :string,
    identity: :string,
    sha256: :string,
    cache: :string,
    source: :string,
    authorization_env: :string,
    json: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()

    with {:ok, descriptors} <- Inventory.load(manifest),
         {:ok, descriptor} <- Inventory.fetch(descriptors, opts[:package], opts[:profile]),
         {:ok, authorization} <- authorization(opts[:authorization_env]),
         {:ok, delivery} <-
           Delivery.run(
             :prebuilt,
             fn -> {:error, "source build is not selected"} end,
             fn ->
               Retrieval.retrieve_and_adopt(
                 descriptor,
                 opts[:target],
                 opts[:identity],
                 opts[:sha256],
                 opts[:cache],
                 source: opts[:source],
                 authorization: authorization
               )
             end
           ) do
      output = if opts[:json], do: encode(delivery), else: render(delivery)
      Mix.shell().info(output)
      :ok
    else
      {:error, %Delivery.Failure{errors: errors}} -> fail(errors, opts[:json] || false)
      {:error, errors} when is_list(errors) -> fail(errors, opts[:json] || false)
      {:error, message} -> fail([message], opts[:json] || false)
    end
  end

  @doc "Parses one exact prebuilt retrieval request."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    for key <- ~w(package profile target identity sha256 cache)a do
      if opts[key] in [nil, ""], do: Mix.raise("--#{key} is required")
    end

    if Path.type(opts[:cache]) != :absolute, do: Mix.raise("--cache must be absolute")

    for key <- ~w(identity sha256)a do
      unless Regex.match?(@digest, opts[key]),
        do: Mix.raise("--#{key} must be a full lowercase SHA-256")
    end

    if opts[:authorization_env] && is_nil(opts[:source]),
      do: Mix.raise("--authorization-env requires --source")

    if opts[:authorization_env] && not Regex.match?(@environment, opts[:authorization_env]),
      do: Mix.raise("--authorization-env must be an uppercase environment variable name")

    opts
  end

  defp authorization(nil), do: {:ok, nil}

  defp authorization(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "authorization environment variable #{name} is not set"}
    end
  end

  defp encode(delivery) do
    result = delivery.value
    entry = result.entry

    CanonicalJSON.encode!(%{
      "schema" => "wotex.native-retrieval@1",
      "selected_delivery_mode" => Atom.to_string(delivery.selected_mode),
      "actual_delivery_mode" => Atom.to_string(delivery.actual_mode),
      "source" => result.source,
      "selected_url" => result.selected_url,
      "delivery_path" => result.delivery_path,
      "build_identity" => entry.manifest.build_identity,
      "payload_identity" => entry.manifest.payload_identity,
      "transport_sha256" => result.transport_sha256,
      "transport_size" => result.transport_size,
      "reused" => entry.reused,
      "state" => "adopted",
      "published" => false
    })
  end

  defp render(delivery) do
    result = delivery.value
    entry = result.entry
    reuse = if entry.reused, do: "reused", else: "adopted"

    "#{reuse} #{entry.manifest.package}/#{entry.manifest.profile}/#{entry.manifest.target} " <>
      "from #{result.source} as #{entry.manifest.build_identity} " <>
      "(#{result.transport_size} bytes, prebuilt; publication not claimed)"
  end

  defp fail(errors, true) do
    CLI.fail(
      CanonicalJSON.encode!(%{
        "schema" => "wotex.native-retrieval@1",
        "selected_delivery_mode" => "prebuilt",
        "actual_delivery_mode" => "prebuilt",
        "result" => "failed",
        "errors" => errors
      })
    )
  end

  defp fail(errors, false), do: CLI.fail(Enum.join(errors, "\n"))
end
