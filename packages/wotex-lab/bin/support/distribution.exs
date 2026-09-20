defmodule Wotex.Lab.Check.Distribution do
  @moduledoc false

  alias Wotex.Lab.Evidence.Digest

  @schema "wotex-lab-distribution/v1"
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @hex_packages ~w(wotex wotex_runtime wotex_binding_http wotex_binding_mqtt
                    wotex_modbus wotex_coap wotex_bacnet wotex_opcua wotex_ble
                    wotex_matter wotex_thread wotex_directory wotex_continuum
                    wotex_nx wotex_conformance wotex_lab)
  @source_paths ~w(source/wotex-lab-workbench.tar source/wotex-lab-oci-context.tar
                   source/wotex-lab-nerves-rpi4.tar)
  @npm ~r{\Anpm/wotex-lab-client-\d+\.\d+\.\d+\.tgz\z}
  @release ~r{\Arelease/wotex-lab-workbench-[a-zA-Z0-9_.-]+\.tar\.gz\z}
  @release_source "release/wotex-lab-workbench-source.tar"

  @spec build_manifest(Path.t(), String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def build_manifest(root, revision, source_digest) do
    files = files(root)

    with true <- valid_revision?(revision),
         true <- is_binary(source_digest) and Regex.match?(@digest, source_digest),
         true <- files != [],
         true <- Enum.all?(files, &(not symlink?(&1))) do
      artifacts =
        Enum.map(files, fn path ->
          %{
            "path" => Path.relative_to(path, root),
            "bytes" => File.stat!(path).size,
            "digest" => Digest.file!(path)
          }
        end)

      {:ok,
       %{
         "schema_version" => @schema,
         "revision" => revision,
         "source_digest" => source_digest,
         "artifacts" => artifacts
       }}
    else
      _ -> {:error, :invalid_distribution}
    end
  end

  @spec validate_manifest(map(), Path.t()) :: :ok | {:error, atom()}
  def validate_manifest(
        %{
          "schema_version" => @schema,
          "revision" => revision,
          "source_digest" => source_digest,
          "artifacts" => artifacts
        } = manifest,
        root
      )
      when map_size(manifest) == 4 and is_list(artifacts) and artifacts != [] do
    paths = Enum.map(artifacts, & &1["path"])

    with true <- valid_revision?(revision),
         true <- is_binary(source_digest) and Regex.match?(@digest, source_digest),
         true <- paths == Enum.sort(paths) and length(paths) == length(Enum.uniq(paths)),
         true <- Enum.all?(artifacts, &valid_artifact?(&1, root)) do
      :ok
    else
      _ -> {:error, :invalid_distribution}
    end
  end

  def validate_manifest(_, _), do: {:error, :invalid_distribution}

  @spec validate_candidate_paths([String.t()], boolean()) :: :ok | {:error, atom()}
  def validate_candidate_paths(paths, require_release?)
      when is_list(paths) and is_boolean(require_release?) do
    releases = Enum.filter(paths, &(is_binary(&1) and String.starts_with?(&1, "release/")))

    with true <- length(paths) == length(Enum.uniq(paths)),
         true <- Enum.all?(paths, &candidate_path?/1),
         true <- Enum.all?(@hex_packages, &(hex_count(paths, &1) == 1)),
         true <- Enum.all?(@source_paths, &(&1 in paths)),
         true <- Enum.count(paths, &Regex.match?(@npm, &1)) == 1,
         true <- valid_release_paths?(releases, require_release?) do
      :ok
    else
      _ -> {:error, :invalid_candidate_layout}
    end
  end

  def validate_candidate_paths(_, _), do: {:error, :invalid_candidate_layout}

  @spec encode(map()) :: {:ok, binary()} | {:error, term()}
  def encode(manifest), do: Wotex.JSON.encode(manifest)

  defp files(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&(File.regular?(&1) and Path.basename(&1) != "manifest.json"))
    |> Enum.sort()
  end

  defp valid_artifact?(artifact, root) when is_map(artifact) and map_size(artifact) == 3 do
    path = artifact["path"]
    bytes = artifact["bytes"]
    digest = artifact["digest"]

    with true <- safe_relative?(path),
         true <- is_integer(bytes) and bytes > 0,
         true <- is_binary(digest) and Regex.match?(@digest, digest),
         absolute = Path.expand(path, root),
         true <- String.starts_with?(absolute, Path.expand(root) <> "/"),
         {:ok, %File.Stat{type: :regular, size: ^bytes}} <- File.lstat(absolute),
         {:ok, ^digest} <- Digest.file(absolute) do
      true
    else
      _ -> false
    end
  end

  defp valid_artifact?(_, _), do: false

  defp safe_relative?(path) when is_binary(path) do
    path != "" and Path.type(path) == :relative and
      not Enum.member?(Path.split(path), "..") and not String.contains?(path, <<0>>)
  end

  defp safe_relative?(_), do: false

  defp candidate_path?(path) when is_binary(path) do
    path in @source_paths or path == @release_source or Regex.match?(@npm, path) or
      Regex.match?(@release, path) or Enum.any?(@hex_packages, &hex_path?(path, &1))
  end

  defp candidate_path?(_), do: false

  defp hex_count(paths, package), do: Enum.count(paths, &hex_path?(&1, package))

  defp hex_path?(path, package) when is_binary(path) do
    Regex.match?(~r{\Ahex/#{Regex.escape(package)}-\d+\.\d+\.\d+\.tar\z}, path)
  end

  defp hex_path?(_, _), do: false

  defp valid_release_paths?([], false), do: true

  defp valid_release_paths?(paths, _required?) do
    length(paths) == 2 and @release_source in paths and
      Enum.count(paths, &Regex.match?(@release, &1)) == 1
  end

  defp valid_revision?("unknown"), do: true

  defp valid_revision?(revision) when is_binary(revision),
    do: Regex.match?(~r/\A[0-9a-f]{40}\z/, revision)

  defp valid_revision?(_), do: false

  defp symlink?(path), do: match?({:ok, %File.Stat{type: :symlink}}, File.lstat(path))
end
