defmodule Wotex.Workspace.NativeArtifact.Identity do
  @moduledoc "Computes full canonical build identities for admitted native artifacts."

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Descriptor

  @revision ~r/^[0-9a-f]{40,64}$/

  @type result :: %{identity: String.t(), canonical: binary(), document: map()}

  @doc "Returns the repository's full current commit identity without changing Git state."
  @spec repository_revision(Path.t()) :: {:ok, String.t()} | {:error, String.t()}
  def repository_revision(root \\ Workspace.root()) do
    case System.cmd("git", ["rev-parse", "HEAD"],
           cd: root,
           env: [{"GIT_OPTIONAL_LOCKS", "0"}, {"GIT_TERMINAL_PROMPT", "0"}],
           stderr_to_stdout: true
         ) do
      {revision, 0} -> {:ok, String.trim(revision)}
      {output, status} -> {:error, "git rev-parse HEAD failed (#{status}): #{String.trim(output)}"}
    end
  end

  @doc "Computes the build identity for one supported descriptor target."
  @spec build(Descriptor.t(), String.t(), String.t(), Manifest.t(), Path.t()) ::
          {:ok, result()} | {:error, String.t()}
  def build(
        descriptor,
        target_name,
        revision,
        %Manifest{} = manifest \\ Manifest.load!(),
        root \\ Workspace.root()
      ) do
    with :ok <- valid_revision(revision),
         {:ok, %{status: :supported}} <- Descriptor.target(descriptor, target_name),
         {:ok, target} <- fetch_target(manifest, target_name),
         {:ok, document} <- document(descriptor, target, revision, manifest, root),
         {:ok, canonical} <- CanonicalJSON.encode(document) do
      {:ok,
       %{
         identity: sha256(canonical),
         canonical: canonical,
         document: document
       }}
    else
      {:ok, %{status: :unsupported, reason: reason}} ->
        {:error, "target #{target_name} is unsupported: #{reason}"}

      {:error, _} = error ->
        error
    end
  end

  @doc "Returns a lowercase full SHA-256 digest."
  @spec sha256(iodata()) :: String.t()
  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp document(descriptor, target, revision, manifest, root) do
    package_root = Path.join(root, "packages/#{descriptor.package}")
    raw = descriptor.raw
    toolchain = Map.fetch!(manifest.native_artifact.toolchains, target.toolchain)
    system = Map.fetch!(manifest.native_artifact.systems, target.system)

    with {:ok, source_entries} <- digest_paths(raw["sources"]["first_party"], package_root),
         {:ok, patch_entries} <- digest_patches(raw["patches"], package_root),
         {:ok, descriptor_toolchain_inputs} <-
           digest_paths(raw["toolchain"]["inputs"], package_root),
         {:ok, root_toolchain_inputs} <- digest_paths(toolchain.inputs, root),
         {:ok, system_inputs} <- digest_paths(system.inputs, root),
         {:ok, descriptor_json} <- CanonicalJSON.encode(raw),
         {:ok, source_json} <- CanonicalJSON.encode(source_entries) do
      {:ok,
       %{
         "schema" => "wotex.native-build-identity@1",
         "descriptor_schema" => raw["schema"],
         "artifact_format" => raw["artifact_format"],
         "descriptor_sha256" => sha256(descriptor_json),
         "package" => descriptor.package,
         "profile" => descriptor.profile,
         "kind" => descriptor.kind,
         "repository_revision" => revision,
         "first_party_source_sha256" => sha256(source_json),
         "first_party_sources" => source_entries,
         "upstream_sources" => raw["sources"]["upstream"],
         "patches" => patch_entries,
         "target" => %{
           "name" => target.name,
           "operating_system" => target.operating_system,
           "architecture" => target.architecture,
           "endianness" => target.endianness,
           "libc" => target.libc,
           "abi" => target.abi
         },
         "toolchain" => %{
           "name" => toolchain.name,
           "identity" => toolchain.identity,
           "inventory_inputs" => root_toolchain_inputs,
           "descriptor_inputs" => descriptor_toolchain_inputs,
           "requirements" => raw["toolchain"]["requirements"],
           "container_digest" => raw["toolchain"]["container_digest"]
         },
         "system" => %{
           "name" => system.name,
           "identity" => system.identity,
           "inputs" => system_inputs
         },
         "build" => raw["build"],
         "qualification" => raw["qualification"],
         "compatibility" => raw["compatibility"],
         "outputs" => raw["outputs"],
         "external_libraries" => raw["external_libraries"],
         "legal" => raw["legal"],
         "native_inputs" => raw["native_inputs"]
       }}
    end
  end

  defp fetch_target(manifest, name) do
    case Map.fetch(manifest.native_artifact.targets, name) do
      {:ok, target} -> {:ok, target}
      :error -> {:error, "undeclared target #{inspect(name)}"}
    end
  end

  defp digest_patches(patches, base) do
    result =
      Enum.reduce_while(patches, {:ok, []}, fn patch, {:ok, entries} ->
        absolute = Path.join(base, patch["path"])

        case File.read(absolute) do
          {:ok, bytes} ->
            actual = sha256(bytes)

            if actual == patch["sha256"] do
              entry = %{"id" => patch["id"], "path" => patch["path"], "sha256" => actual}
              {:cont, {:ok, [entry | entries]}}
            else
              {:halt,
               {:error,
                "#{patch["path"]}: patch digest mismatch; expected #{patch["sha256"]}, got #{actual}"}}
            end

          {:error, reason} ->
            {:halt, {:error, "#{patch["path"]}: #{:file.format_error(reason)}"}}
        end
      end)

    case result do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _} = error -> error
    end
  end

  defp digest_paths(paths, base) do
    result =
      Enum.reduce_while(paths, {:ok, []}, fn relative, {:ok, entries} ->
        case digest_path(Path.join(base, relative), relative) do
          {:ok, additions} -> {:cont, {:ok, additions ++ entries}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, entries} -> {:ok, Enum.sort_by(entries, & &1["path"])}
      {:error, _} = error -> error
    end
  end

  defp digest_path(absolute, relative) do
    case File.lstat(absolute) do
      {:ok, %{type: :regular, mode: mode}} ->
        case File.read(absolute) do
          {:ok, bytes} ->
            {:ok,
             [
               %{
                 "path" => relative,
                 "kind" => "file",
                 "mode" => Bitwise.band(mode, 0o777),
                 "sha256" => sha256(bytes)
               }
             ]}

          {:error, reason} ->
            {:error, "#{relative}: #{:file.format_error(reason)}"}
        end

      {:ok, %{type: :directory}} ->
        digest_directory(absolute, relative)

      {:ok, %{type: type}} ->
        {:error, "#{relative}: source input kind #{type} is not admitted"}

      {:error, reason} ->
        {:error, "#{relative}: #{:file.format_error(reason)}"}
    end
  end

  defp digest_directory(absolute, relative) do
    case File.ls(absolute) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.reduce_while({:ok, []}, fn name, {:ok, entries} ->
          child_relative = Path.join(relative, name)

          case digest_path(Path.join(absolute, name), child_relative) do
            {:ok, additions} -> {:cont, {:ok, additions ++ entries}}
            {:error, _} = error -> {:halt, error}
          end
        end)

      {:error, reason} ->
        {:error, "#{relative}: #{:file.format_error(reason)}"}
    end
  end

  defp valid_revision(revision) do
    if is_binary(revision) and Regex.match?(@revision, revision),
      do: :ok,
      else: {:error, "repository revision must be a full lowercase hexadecimal identity"}
  end
end
