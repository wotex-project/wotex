defmodule Wotex.Matter.SoftwareManifest do
  @moduledoc false

  @sdk_revision "250a9e6c50ee2068107f3c4808b680f5f2925415"
  @sdk_sha256 "83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628"
  @image "node:24-bookworm@sha256:6dac556d980b7f0e5498d08f08cee0ca67798b4ad6c23964a9214920e67758d0"
  @patterns [
    "lib/**/*.ex",
    "native/**/*",
    "priv/**/*.json",
    "test/**/*.ex",
    "test/**/*.exs",
    "test/support/software/**/*",
    "test/native/*.cpp",
    "bin/check_*.exs",
    "config/**/*.exs",
    ".check.exs",
    ".credo.exs",
    ".formatter.exs",
    "coveralls.json",
    "docs/specs/fixtures/*.json",
    "mix.exs",
    "mix.lock"
  ]

  @spec sdk_revision() :: String.t()
  def sdk_revision, do: @sdk_revision

  @spec sdk_sha256() :: String.t()
  def sdk_sha256, do: @sdk_sha256

  @spec image() :: String.t()
  def image, do: @image

  @spec arguments(term(), String.t()) :: String.t()
  def arguments(["--workspace", path], root) when is_binary(path) do
    if byte_size(path) not in 1..4096 or not String.valid?(path) or
         String.contains?(path, [<<0>>, "\n", "\r"]) or Path.type(path) != :absolute or
         Enum.any?(Path.split(path), &(&1 in [".", ".."])),
       do: fail(:invalid_workspace)

    workspace = Path.expand(path)

    if workspace == root or String.starts_with?(workspace, root <> "/"),
      do: fail(:workspace_inside_source)

    assert_directories!(Path.dirname(workspace))

    case File.lstat(workspace) do
      {:error, :enoent} -> workspace
      {:ok, %{type: :directory}} -> workspace
      _ -> fail(:invalid_workspace)
    end
  end

  def arguments(_, _), do: fail(:invalid_arguments)

  @spec identity(String.t()) :: map()
  def identity(root) do
    files =
      @patterns
      |> Enum.flat_map(&Path.wildcard(Path.join(root, &1)))
      |> Enum.filter(&File.regular?/1)
      |> Enum.uniq()
      |> Map.new(&{Path.relative_to(&1, root), digest(&1)})

    canonical =
      files
      |> Enum.sort()
      |> Enum.map(fn {path, value} -> [path, <<0>>, value, "\n"] end)

    %{
      "source_sha256" => hash(IO.iodata_to_binary(canonical)),
      "source_files_sha256" => files
    }
  end

  @spec read(String.t()) :: map()
  def read(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} when size <= 1_048_576 ->
        case Wotex.JSON.decode(File.read!(path), max_bytes: 1_048_576) do
          {:ok, value} when is_map(value) -> value
          _ -> fail(:invalid_manifest)
        end

      _ ->
        fail(:invalid_manifest)
    end
  end

  @spec write(String.t(), map()) :: :ok
  def write(path, value) do
    temporary = path <> ".temporary"
    File.write!(temporary, Jason.encode!(value, pretty: true) <> "\n", [:exclusive])
    File.rename!(temporary, path)
  end

  @spec verify_local(String.t(), String.t(), map(), :native | :software) :: map()
  def verify_local(root, workspace, manifest, required_mode) do
    verify_identity!(root, manifest)
    mode = manifest["mode"]

    unless mode in ["native", "software"] and
             (required_mode == :native or mode == "software"),
           do: fail(:software_fixture_required)

    verify_artifacts!(workspace, manifest["files"], mode)
    verify_native_manifest!(root, workspace)
    manifest
  end

  defp verify_identity!(root, manifest) do
    expected = %{
      "schema" => "wotex.matter.software-workspace@1",
      "status" => "ready",
      "sdk_revision" => @sdk_revision,
      "sdk_archive_sha256" => @sdk_sha256,
      "container_image" => @image,
      "target" => "x86_64-linux-gnu",
      "source" => identity(root)
    }

    unless Enum.all?(expected, fn {key, value} -> manifest[key] == value end),
      do: fail(:manifest_mismatch)
  end

  defp verify_artifacts!(workspace, files, mode) do
    required = required_files(mode)

    unless is_map(files) and Enum.sort(Map.keys(files)) == Enum.sort(required),
      do: fail(:manifest_files)

    for {name, expected_hash} <- files do
      unless safe_name?(name) and valid_hash?(expected_hash), do: fail(:manifest_files)
      path = Path.join(workspace, name)
      assert_directories!(Path.dirname(path))

      unless match?({:ok, %{type: :regular}}, File.lstat(path)) and digest(path) == expected_hash,
        do: fail(:artifact_hash_mismatch)
    end
  end

  defp verify_native_manifest!(root, workspace) do
    native = read(Path.join(workspace, "native-manifest.json"))

    unless native["schema"] == "wotex.native-build" and native["version"] == 1 and
             native["package"] == "wotex_matter" and
             native["source_files"] == identity(root)["source_files_sha256"],
           do: fail(:native_manifest_mismatch)

    unless is_map(native["logs"]) and map_size(native["logs"]) in 1..256,
      do: fail(:native_manifest_mismatch)

    verify_logs!(workspace, native["logs"])
  end

  defp verify_logs!(workspace, logs) do
    for {name, expected_hash} <- logs do
      unless safe_name?(name) and String.starts_with?(name, "logs/") and valid_hash?(expected_hash),
        do: fail(:manifest_files)

      path = Path.join(workspace, name)
      assert_directories!(Path.dirname(path))
      unless digest(path) == expected_hash, do: fail(:artifact_hash_mismatch)
    end
  end

  @spec required_files(String.t()) :: [String.t()]
  def required_files("native"),
    do: [
      "bin/wotex-matter-host",
      "bin/wotex-matter-host-sanitized",
      "bin/wotex-matter-contract-driver",
      "bin/wotex-matter-contract-driver-sanitized",
      "native-manifest.json"
    ]

  def required_files("software"),
    do:
      required_files("native") ++
        [
          "bin/wotex-matter-flow-host",
          "bin/wotex-matter-flow-host-sanitized",
          "bin/wotex-matter-resource-host",
          "bin/wotex-matter-resource-host-sanitized",
          "bin/wotex-matter-controller-test",
          "bin/wotex-matter-controller-test-sanitized",
          "bin/chip-lighting-app",
          "bin/chip-all-clusters-app",
          "bin/chip-bridge-app",
          "paa/Chip-Test-PAA-FFF1-Cert.der",
          "paa/Chip-Test-PAA-NoVID-Cert.der",
          "paa/Chip-Test-PAA-NoVID-ToResignPAIs-Cert.der"
        ]

  @spec file_hashes(String.t(), String.t()) :: map()
  def file_hashes(workspace, mode),
    do: Map.new(required_files(mode), &{&1, digest(Path.join(workspace, &1))})

  @spec digest(String.t()) :: String.t()
  def digest(path) do
    unless match?(
             {:ok, %{type: :regular, size: size}} when size <= 1_073_741_824,
             File.lstat(path)
           ),
           do: fail(:invalid_build_artifact)

    path
    |> File.stream!(65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn bytes, context ->
      :crypto.hash_update(context, bytes)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @spec hash(binary()) :: String.t()
  def hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  @spec assert_directories!(String.t()) :: :ok
  def assert_directories!(path) do
    [root | segments] = Path.split(path)

    _ =
      Enum.reduce(segments, root, fn segment, parent ->
        current = Path.join(parent, segment)

        case File.lstat(current) do
          {:ok, %{type: :directory}} -> current
          _ -> fail(:invalid_workspace)
        end
      end)

    :ok
  end

  defp safe_name?(name) when is_binary(name) do
    byte_size(name) in 1..4096 and Path.type(name) == :relative and
      not String.contains?(name, ["\\", <<0>>]) and
      Enum.all?(String.split(name, "/", trim: true), &(&1 not in [".", ".."]))
  end

  defp safe_name?(_), do: false
  defp valid_hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp fail(code), do: Mix.raise(Atom.to_string(code))
end
