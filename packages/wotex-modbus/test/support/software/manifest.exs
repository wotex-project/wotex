defmodule Wotex.Modbus.SoftwareManifest do
  @moduledoc false

  @descriptor "priv/native-artifacts/software-peer.json"
  @descriptor_keys ~w(artifact_format build compatibility external_libraries kind legal native_inputs outputs package patches profile qualification retrieval schema sources targets toolchain)
  @source_keys ~w(name revision sha256 url)
  @inputs [
    @descriptor,
    "test/interop/libmodbus/server.c",
    "test/interop/libmodbus/Dockerfile",
    "test/interop/native/command.c",
    "test/support/software/command.exs",
    "test/support/software/manifest.exs",
    "test/support/software/fixture.exs"
  ]
  @patterns [
    "lib/**/*.ex",
    "test/**/*.ex",
    "test/**/*.exs",
    "test/**/*.c",
    "test/**/Dockerfile",
    "bin/*",
    "priv/fixtures/*.json",
    "priv/native-artifacts/*.json",
    "mix.exs",
    "mix.lock"
  ]

  @spec source(String.t()) :: %{String.t() => String.t()}
  def source(root) do
    descriptor = read(Path.join(root, @descriptor))

    case descriptor do
      %{"sources" => %{"first_party" => first_party, "upstream" => [source]} = sources} ->
        if admitted_descriptor?(descriptor) and admitted_sources?(sources, first_party) and
             admitted_source?(source) do
          source
        else
          fail(:software_source_descriptor_invalid)
        end

      _ ->
        fail(:software_source_descriptor_invalid)
    end
  end

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
    source = source(root)

    expected = %{
      "schema" => "wotex.modbus.native-peer@1",
      "status" => "ready",
      "source_commit" => source["revision"],
      "source_url" => source["url"],
      "source_archive_sha256" => source["sha256"],
      "inputs" => inputs(root)
    }

    unless Enum.all?(expected, fn {key, value} -> manifest[key] == value end),
      do: fail(:manifest_mismatch)

    unless digest(Path.join(workspace, "source.tar.gz")) == source["sha256"],
      do: fail(:archive_hash_mismatch)

    files = manifest["files"]

    required = [
      "source.tar.gz",
      "command",
      "compiler.json",
      "native-toolchain.json",
      "context/source.tar.gz",
      "context/server.c",
      "context/Dockerfile"
    ]

    unless is_map(files) and Enum.sort(Map.keys(files)) == Enum.sort(required),
      do: fail(:manifest_files)

    for {name, expected_hash} <- files do
      unless safe_name?(name) and valid_hash?(expected_hash), do: fail(:manifest_files)
      path = Path.join(workspace, name)

      unless match?({:ok, %{type: :regular}}, File.lstat(path)) and digest(path) == expected_hash,
        do: fail(:artifact_hash_mismatch)
    end

    manifest
  end

  @spec archive_members(term()) :: :ok
  def archive_members(entries) when is_list(entries) and length(entries) in 1..4096 do
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

    unless total <= 33_554_432, do: fail(:unsafe_archive)
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

  defp safe_name?(name) when is_binary(name) do
    byte_size(name) in 1..4096 and Path.type(name) == :relative and
      not String.contains?(name, ["\\", <<0>>]) and
      Enum.all?(String.split(name, "/", trim: true), &(&1 not in [".", ".."]))
  end

  defp safe_name?(_), do: false

  defp admitted_descriptor?(descriptor) do
    Enum.sort(Map.keys(descriptor)) == @descriptor_keys and
      descriptor["schema"] == "wotex.native-artifact-descriptor@2" and
      descriptor["artifact_format"] == "wotex.native-artifact@1" and
      descriptor["package"] == "wotex-modbus" and descriptor["profile"] == "software-peer" and
      descriptor["kind"] == "independent-peer-image"
  end

  defp admitted_sources?(sources, first_party) do
    Enum.sort(Map.keys(sources)) == ["first_party", "upstream"] and
      valid_first_party?(first_party)
  end

  defp admitted_source?(source) when is_map(source) do
    Enum.sort(Map.keys(source)) == @source_keys and source["name"] == "libmodbus" and
      valid_revision?(source["revision"]) and valid_hash?(source["sha256"]) and
      source["url"] ==
        "https://codeload.github.com/stephane/libmodbus/tar.gz/" <> source["revision"]
  end

  defp admitted_source?(_), do: false
  defp valid_revision?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{40}\z/, value)
  defp valid_hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp valid_first_party?(paths) when is_list(paths) and paths != [] do
    Enum.uniq(paths) == paths and Enum.all?(paths, &safe_name?/1)
  end

  defp valid_first_party?(_), do: false
  defp fail(code), do: Mix.raise(Atom.to_string(code))
end
