defmodule Mix.Tasks.Wotex.Native.Closure do
  @shortdoc "Checks one assembled target's native dependency closure"

  @moduledoc """
  Resolves every reachable ELF dependency using only verified cache artifacts
  and one exact target root filesystem:

      mix wotex.native.closure --cache /absolute/cache --rootfs /absolute/rootfs \
        --target TARGET --artifact PACKAGE/PROFILE/FULL_SHA256 [--artifact ...] [--json]

  The command never consults host library paths or linker caches. Every cache
  artifact is revalidated before inspection. Non-ELF formats require their own
  explicit checker and never fall back to filename matching.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.Cache
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.DependencyClosure
  alias Wotex.Workspace.NativeArtifact.DependencyClosure.Artifact
  alias Wotex.Workspace.NativeArtifact.Inventory

  @digest ~r/^[0-9a-f]{64}$/
  @switches [
    cache: :string,
    rootfs: :string,
    target: :string,
    artifact: :keep,
    json: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()

    with {:ok, target} <- fetch_target(manifest, opts[:target]),
         {:ok, system} <- Map.fetch(manifest.native_artifact.systems, target.system),
         {:ok, descriptors} <- Inventory.load(manifest),
         {:ok, artifacts} <- load_artifacts(opts, descriptors),
         {:ok, result} <- DependencyClosure.check(artifacts, opts[:rootfs], target, system) do
      output = if opts[:json], do: encode(result), else: render(result)
      Mix.shell().info(output)
      :ok
    else
      :error -> fail(["target system is not admitted"], opts[:json] || false)
      {:error, errors} when is_list(errors) -> fail(errors, opts[:json] || false)
      {:error, message} -> fail([message], opts[:json] || false)
    end
  end

  @doc "Parses an exact cache-artifact assembly and target root filesystem."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    for key <- ~w(cache rootfs target)a do
      if opts[key] in [nil, ""], do: Mix.raise("--#{key} is required")
    end

    for key <- ~w(cache rootfs)a do
      if Path.type(opts[key]) != :absolute, do: Mix.raise("--#{key} must be absolute")
    end

    case Keyword.get_values(opts, :artifact) do
      [] -> Mix.raise("at least one --artifact PACKAGE/PROFILE/FULL_SHA256 is required")
      specs -> Enum.each(specs, &parse_artifact!/1)
    end

    opts
  end

  @doc "Parses one package/profile/full-build-identity artifact selection."
  @spec parse_artifact!(String.t()) :: {String.t(), String.t(), String.t()}
  def parse_artifact!(spec) do
    case String.split(spec, "/", parts: 3) do
      [package, profile, identity]
      when package != "" and profile != "" and identity != "" ->
        if Regex.match?(@digest, identity) do
          {package, profile, identity}
        else
          Mix.raise("artifact identity must be a full lowercase SHA-256: #{spec}")
        end

      _ ->
        Mix.raise("artifact must be PACKAGE/PROFILE/FULL_SHA256: #{spec}")
    end
  end

  defp fetch_target(manifest, name) do
    case Map.fetch(manifest.native_artifact.targets, name) do
      {:ok, target} -> {:ok, target}
      :error -> {:error, "undeclared native artifact target #{name}"}
    end
  end

  defp load_artifacts(opts, descriptors) do
    opts
    |> Keyword.get_values(:artifact)
    |> Enum.reduce_while({:ok, []}, fn spec, {:ok, artifacts} ->
      {package, profile, identity} = parse_artifact!(spec)

      with {:ok, descriptor} <- Inventory.fetch(descriptors, package, profile),
           {:ok, entry} <-
             Cache.inspect(opts[:cache], identity, descriptor, opts[:target]) do
        artifact = %Artifact{
          name: "#{package}/#{profile}/#{identity}",
          path: Path.join(entry.path, "payload"),
          target: entry.manifest.target,
          build_identity: entry.manifest.build_identity,
          payload_identity: entry.manifest.payload_identity,
          external_libraries: descriptor.raw["external_libraries"]
        }

        {:cont, {:ok, [artifact | artifacts]}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> reverse_artifacts()
  end

  defp reverse_artifacts({:ok, artifacts}), do: {:ok, Enum.reverse(artifacts)}
  defp reverse_artifacts({:error, _} = error), do: error

  defp encode(result) do
    CanonicalJSON.encode!(%{
      "schema" => "wotex.native-dependency-closure@1",
      "target" => result.target,
      "architecture" => result.architecture,
      "endianness" => result.endianness,
      "system" => result.system,
      "system_identity" => result.system_identity,
      "artifacts" => result.artifacts,
      "files" => result.files,
      "edges" => result.edges,
      "result" => "passed"
    })
  end

  defp render(result) do
    header =
      "closed #{result.target} against #{result.system}/#{result.system_identity}: " <>
        "#{length(result.artifacts)} artifacts, #{length(result.files)} ELF files, " <>
        "#{length(result.edges)} dependency edges"

    files =
      Enum.map(result.files, fn file ->
        dependencies =
          case file["needed"] do
            [] -> "no shared dependencies"
            needed -> Enum.join(needed, ", ")
          end

        "  #{file["id"]}  #{file["class"]}/#{file["architecture"]}/#{file["endianness"]}  " <>
          dependencies
      end)

    Enum.join([header | files], "\n")
  end

  defp fail(errors, true) do
    CLI.fail(
      CanonicalJSON.encode!(%{
        "schema" => "wotex.native-dependency-closure@1",
        "result" => "failed",
        "errors" => errors
      })
    )
  end

  defp fail(errors, false), do: CLI.fail(Enum.join(errors, "\n"))
end
