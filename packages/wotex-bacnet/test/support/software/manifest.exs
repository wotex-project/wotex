defmodule Wotex.BACnet.SoftwareManifest do
  @moduledoc false

  @source_inventory "priv/fixtures/software-sources-v1.json"
  @inputs [
    @source_inventory,
    "test/interop/cstack/CMakeLists.txt",
    "test/interop/cstack/Dockerfile.software",
    "test/interop/cstack/peer.c",
    "test/interop/cstack/peer.h",
    "test/interop/cstack/control.c",
    "test/interop/cstack/property_peer.c",
    "test/interop/cstack/property_peer.h",
    "test/interop/native/command.c",
    "test/interop/native/command_group_fault.c",
    "test/interop/native/command_launcher.c",
    "test/interop/run_software.sh",
    "test/support/software/command.exs",
    "test/support/software/manifest.exs",
    "test/support/software/package.exs",
    "test/support/software/fixture.exs",
    "test/support/software/run.exs",
    "test/support/software_formatter.ex",
    "lib/mix/tasks/wotex.bacnet.software.build.ex",
    "lib/mix/tasks/wotex.bacnet.software.run.ex",
    "mix.exs",
    "mix.lock"
  ]
  @patterns [
    "lib/**/*.ex",
    "test/**/*.ex",
    "test/**/*.exs",
    "test/**/*.c",
    "test/**/*.h",
    "test/**/*.json",
    "test/**/*.sh",
    "test/**/CMakeLists.txt",
    "test/**/Dockerfile*",
    "bin/*",
    "priv/fixtures/*.json",
    "mix.exs",
    "mix.lock"
  ]

  @type sources :: %{runtime: map(), peer: map(), sha256: String.t()}

  @spec sources(String.t()) :: sources()
  def sources(root) do
    path = Path.join(root, @source_inventory)

    with {:ok, %{type: :regular, size: size}} when size in 1..16_384 <- File.lstat(path),
         {:ok, bytes} <- File.read(path),
         {:ok, inventory} when is_map(inventory) <- Jason.decode(bytes),
         {:ok, runtime, peer} <- validate_sources(inventory) do
      %{runtime: runtime, peer: peer, sha256: hash(bytes)}
    else
      _ -> fail(:invalid_source_inventory)
    end
  end

  @spec pin(sources()) :: String.t()
  def pin(%{peer: %{"commit" => value}}), do: value
  @spec archive_sha(sources()) :: String.t()
  def archive_sha(%{peer: %{"sha256" => value}}), do: value
  @spec source_url(sources()) :: String.t()
  def source_url(%{peer: %{"url" => value}}), do: value
  @spec inputs(String.t()) :: %{String.t() => String.t()}
  def inputs(root), do: Map.new(@inputs, &{&1, digest(Path.join(root, &1))})
  @spec digest(String.t()) :: String.t()
  def digest(path), do: hash(File.read!(path))
  @spec hash(binary()) :: String.t()
  def hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  @spec arguments(term(), String.t()) :: String.t()
  def arguments(["--workspace", path], root) when is_binary(path) do
    if byte_size(path) not in 1..4096 or String.contains?(path, <<0>>) or
         Path.type(path) != :absolute,
       do: fail(:invalid_workspace)

    workspace = Path.expand(path)

    if workspace == root or String.starts_with?(workspace, root <> "/"),
      do: fail(:workspace_inside_source)

    case File.lstat(workspace) do
      {:error, :enoent} -> workspace
      {:ok, %{type: :directory}} -> workspace
      _ -> fail(:invalid_workspace)
    end
  end

  def arguments(_, _), do: fail(:invalid_arguments)

  @spec read(String.t()) :: map()
  def read(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} when size <= 1_048_576 ->
        case Jason.decode(File.read!(path)) do
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

  @spec verify_local(String.t(), String.t(), map()) :: map()
  def verify_local(root, workspace, manifest) do
    sources = sources(root)

    expected = %{
      "schema" => "wotex.bacnet.native-peer@1",
      "status" => "ready",
      "source_commit" => pin(sources),
      "source_url" => source_url(sources),
      "source_archive_sha256" => archive_sha(sources),
      "source_inventory_sha256" => sources.sha256,
      "inputs" => inputs(root)
    }

    unless Enum.all?(expected, fn {key, value} -> manifest[key] == value end),
      do: fail(:manifest_mismatch)

    unless bounded_file?(workspace, "source.tar.gz"), do: fail(:artifact_hash_mismatch)

    unless digest(Path.join(workspace, "source.tar.gz")) == archive_sha(sources),
      do: fail(:archive_hash_mismatch)

    files = manifest["files"]

    required = [
      "source.tar.gz",
      "bacstack.tar",
      "bacstack-source.json",
      "command",
      "compiler.json",
      "native-toolchain.json",
      "context/source.tar.gz",
      "context/CMakeLists.txt",
      "context/Dockerfile.software",
      "context/peer.c",
      "context/peer.h",
      "context/control.c",
      "context/property_peer.c",
      "context/property_peer.h"
    ]

    unless is_map(files) and Enum.sort(Map.keys(files)) == Enum.sort(required),
      do: fail(:manifest_files)

    for {name, expected_hash} <- files do
      unless safe_name?(name) and valid_hash?(expected_hash), do: fail(:manifest_files)
      path = Path.join(workspace, name)

      unless bounded_file?(workspace, name) and digest(path) == expected_hash,
        do: fail(:artifact_hash_mismatch)
    end

    manifest
  end

  @spec archive_members(term()) :: :ok
  def archive_members(entries) when is_list(entries) and length(entries) in 1..4096 do
    names =
      Enum.map(entries, fn
        {name, _, _, _, _, _, _} -> name
        _ -> fail(:unsafe_archive)
      end)

    unless length(Enum.uniq(names)) == length(names), do: fail(:unsafe_archive)

    total =
      Enum.reduce(entries, 0, fn
        {name, type, size, _, _, _, _}, total
        when type in [:regular, :directory] and is_integer(size) and size >= 0 ->
          name = List.to_string(name)
          unless safe_name?(name), do: fail(:unsafe_archive)
          total + size

        _, _ ->
          fail(:unsafe_archive)
      end)

    unless total <= 67_108_864, do: fail(:unsafe_archive)
    :ok
  end

  def archive_members(_), do: fail(:unsafe_archive)

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
      |> Enum.map(fn {path, value} -> path <> <<0>> <> value <> "\n" end)

    %{"source_sha256" => hash(IO.iodata_to_binary(canonical)), "source_files_sha256" => files}
  end

  @spec git_identity(term()) :: {String.t(), String.t()}
  def git_identity({:ok, output, 0}) when is_binary(output) do
    case String.split(output, "\n", trim: true) do
      [commit, tree] ->
        unless Regex.match?(~r/\A[0-9a-f]{40}\z/, commit) and
                 Regex.match?(~r/\A[0-9a-f]{40}\z/, tree),
               do: fail(:invalid_git_identity)

        {commit, tree}

      _ ->
        fail(:invalid_git_identity)
    end
  end

  def git_identity(_), do: fail(:invalid_git_identity)

  # Parses `git rev-parse --show-prefix` run from the package root into the
  # package path recorded in evidence and the `HEAD:<prefix>` name of its
  # subtree. A package at the repository root has path `.` and subtree `HEAD:`.
  @spec git_package(term()) :: {String.t(), String.t()}
  def git_package({:ok, output, 0}) when is_binary(output) do
    case String.split(output, "\n") do
      ["", ""] ->
        {".", "HEAD:"}

      [prefix, ""] ->
        unless String.ends_with?(prefix, "/") and safe_name?(prefix),
          do: fail(:invalid_git_identity)

        {String.trim_trailing(prefix, "/"), "HEAD:" <> prefix}

      _ ->
        fail(:invalid_git_identity)
    end
  end

  def git_package(_), do: fail(:invalid_git_identity)

  @spec ordinary_file?(String.t(), String.t()) :: boolean()
  def ordinary_file?(root, name) do
    if safe_name?(name) do
      parts = Path.split(name)

      result =
        parts
        |> Enum.with_index(1)
        |> Enum.reduce_while(root, fn {part, index}, directory ->
          path = Path.join(directory, part)
          type = if index == length(parts), do: :regular, else: :directory

          if match?({:ok, %{type: ^type}}, File.lstat(path)),
            do: {:cont, path},
            else: {:halt, false}
        end)

      is_binary(result)
    else
      false
    end
  end

  defp bounded_file?(root, name) do
    ordinary_file?(root, name) and
      match?({:ok, %{size: size}} when size <= 16_777_216, File.stat(Path.join(root, name)))
  end

  defp safe_name?(name) when is_binary(name) do
    byte_size(name) in 1..4096 and Path.type(name) == :relative and
      not String.contains?(name, ["\\", <<0>>]) and
      Enum.all?(String.split(name, "/", trim: true), &(&1 not in [".", ".."]))
  end

  defp safe_name?(_), do: false

  defp validate_sources(inventory) do
    with true <-
           exact_keys?(inventory, ~w(format version status runtime sources)) and
             inventory["format"] == "wotex.software.sources" and
             inventory["version"] == "1.0.0" and inventory["status"] == "executed" and
             inventory["runtime"] == "BEAM BACstack; no production executable",
         sources when is_list(sources) and length(sources) == 2 <- inventory["sources"],
         true <- Enum.all?(sources, &is_map/1),
         by_name when map_size(by_name) == 2 <- Map.new(sources, &{&1["name"], &1}),
         %{} = runtime <- by_name["bacstack"],
         %{} = peer <- by_name["bacnet-stack"],
         true <- valid_runtime_source?(runtime),
         true <- valid_peer_source?(peer) do
      {:ok, runtime, peer}
    else
      _ -> {:error, :invalid_source_inventory}
    end
  end

  defp valid_runtime_source?(source) do
    exact_keys?(
      source,
      ~w(name role version url hex_outer_sha256 hex_inner_checksum)
    ) and source["name"] == "bacstack" and source["role"] == "runtime_hex_dependency" and
      is_binary(source["version"]) and
      Regex.match?(~r/\A\d+\.\d+\.\d+\z/, source["version"]) and
      source["url"] ==
        "https://repo.hex.pm/tarballs/bacstack-#{source["version"]}.tar" and
      valid_hash?(source["hex_outer_sha256"]) and valid_hash?(source["hex_inner_checksum"])
  end

  defp valid_peer_source?(source) do
    exact_keys?(source, ~w(name role commit url sha256)) and
      source["name"] == "bacnet-stack" and
      source["role"] == "independent_software_peer" and
      is_binary(source["commit"]) and Regex.match?(~r/\A[0-9a-f]{40}\z/, source["commit"]) and
      source["url"] ==
        "https://codeload.github.com/bacnet-stack/bacnet-stack/tar.gz/#{source["commit"]}" and
      valid_hash?(source["sha256"])
  end

  defp exact_keys?(map, keys), do: Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp valid_hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp fail(code), do: Mix.raise(Atom.to_string(code))
end
