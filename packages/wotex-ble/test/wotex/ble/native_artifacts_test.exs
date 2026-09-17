defmodule Wotex.BLE.NativeArtifactsTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.BLE.BlueZ.{Artifacts, Executable}
  alias Wotex.BLE.Error

  doctest Artifacts

  @digest String.duplicate("a", 64)
  @selectors [
    executable: "/missing/bluez-native",
    executable_sha256: @digest,
    guardian: "/missing/custody",
    guardian_sha256: @digest
  ]

  @fixtures Path.expand("../../../priv/fixtures/native-port-v1.json", __DIR__)
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")
  @names %{
    "executable" => :executable,
    "executable_sha256" => :executable_sha256,
    "guardian" => :guardian,
    "guardian_sha256" => :guardian_sha256
  }

  for fixture <- @fixtures, fixture["operation"] == "native_artifact_selectors" do
    @fixture fixture
    test "#{fixture["id"]} executes pure native selectors without file lookup" do
      options =
        Enum.map(@fixture["input"]["selectors"], fn [key, value] ->
          {Map.fetch!(@names, key), value}
        end)

      actual =
        case Artifacts.new(options) do
          {:ok, _} ->
            %{"accepted" => true}

          {:error, error} ->
            %{
              "accepted" => false,
              "code" => Atom.to_string(error.code),
              "field" => Atom.to_string(error.field)
            }
        end

      assert actual == @fixture["expectation"]["value"]
    end
  end

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-native-artifacts-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, directory: directory}
  end

  test "WBL-B01 pure selectors accept no executable or environment dependency" do
    assert {:ok, selected} = Artifacts.new(@selectors)
    assert {:ok, ^selected} = Artifacts.new(selected)
    assert selected.executable == "/missing/bluez-native"
    refute inspect(selected) =~ "/missing"
    assert inspect(selected) =~ @digest
  end

  test "WBL-B01 missing, extra, duplicate and forged selectors are rejected" do
    for invalid <- [nil, [], %{}, [owner: self()] ++ @selectors, [@selectors | :improper]] do
      assert {:error, %Error{code: :invalid_options}} = Artifacts.new(invalid)
    end

    for key <- Keyword.keys(@selectors) do
      assert {:error, %Error{code: :invalid_options}} =
               Artifacts.new(Keyword.delete(@selectors, key))

      assert {:error, %Error{code: :invalid_options}} =
               Artifacts.new([{key, Keyword.fetch!(@selectors, key)} | @selectors])
    end

    assert {:ok, selected} = Artifacts.new(@selectors)
    assert {:error, %Error{code: :invalid_options}} = Artifacts.new(Map.put(selected, :extra, true))
    assert {:error, %Error{code: :invalid_options}} = Artifacts.new(Map.delete(selected, :guardian))
  end

  test "WBL-B01 path and digest boundaries reject malformed selectors" do
    for path <- [
          nil,
          false,
          [],
          "",
          "relative",
          "/contains\0byte",
          <<255>>,
          "/" <> String.duplicate("x", 4096)
        ],
        field <- [:executable, :guardian] do
      assert {:error, %Error{code: :invalid_options}} =
               Artifacts.new(Keyword.put(@selectors, field, path))
    end

    for digest <- [
          nil,
          false,
          "",
          String.duplicate("a", 63),
          String.duplicate("a", 65),
          String.duplicate("A", 64),
          String.duplicate("g", 64),
          <<0::512>>
        ],
        field <- [:executable_sha256, :guardian_sha256] do
      assert {:error, %Error{code: :invalid_options}} =
               Artifacts.new(Keyword.put(@selectors, field, digest))
    end
  end

  property "WBL-B01 exact lowercase digest selectors remain pure" do
    check all(bytes <- binary(length: 32)) do
      digest = Base.encode16(bytes, case: :lower)
      assert {:ok, selected} = Artifacts.new(Keyword.put(@selectors, :executable_sha256, digest))
      assert selected.executable_sha256 == digest
    end
  end

  test "WBL-B01 verifies both independent executable identities", context do
    {executable, digest} = file(context, "sdk", <<0, 255, 42>>)
    {guardian, guardian_digest} = file(context, "guardian", "independent guardian fixture")

    assert {:ok, selected} =
             Artifacts.new(
               executable: executable,
               executable_sha256: digest,
               guardian: guardian,
               guardian_sha256: guardian_digest
             )

    assert {:ok, admitted} = Artifacts.verify(selected, deadline())
    assert admitted.executable.path == executable
    assert admitted.executable.bytes == 3
    assert admitted.executable.sha256 == digest
    assert admitted.guardian.path == guardian
    assert admitted.guardian.sha256 == guardian_digest
    assert admitted.guardian.identity != admitted.executable.identity
    refute inspect(admitted) =~ context.directory
  end

  test "WBL-B01 missing and mismatched files use stable field-specific errors", context do
    {path, digest} = file(context, "sdk", "fixture")

    assert {:error, %Error{code: :transport_unavailable, field: :executable, details: %{}}} =
             Executable.verify(Path.join(context.directory, "missing"), digest, deadline())

    assert {:error,
            %Error{
              code: :incompatible_backend,
              field: :executable,
              class: :permanent,
              details: %{}
            }} =
             Executable.verify(path, @digest, deadline())

    selectors = [
      executable: path,
      executable_sha256: digest,
      guardian: path,
      guardian_sha256: @digest
    ]

    assert {:error, %Error{code: :incompatible_backend, field: :guardian}} =
             Artifacts.verify(selectors, deadline())

    selectors = Keyword.put(selectors, :guardian, Path.join(context.directory, "missing-guardian"))

    assert {:error, %Error{code: :transport_unavailable, field: :guardian}} =
             Artifacts.verify(selectors, deadline())
  end

  test "WBL-B01 regular executable file admission excludes links, directories and empty files",
       context do
    {path, digest} = file(context, "sdk", "fixture")
    link = Path.join(context.directory, "link")
    File.ln_s!(path, link)
    {empty, _} = file(context, "empty", "")

    for rejected <- [link, empty, context.directory] do
      assert {:error, %Error{code: :transport_unavailable}} =
               Executable.verify(rejected, digest, deadline())
    end

    File.chmod!(path, 0o600)

    assert {:error, %Error{code: :transport_unavailable}} =
             Executable.verify(path, digest, deadline())
  end

  test "WBL-B01 oversized sparse file fails before content hashing", context do
    path = Path.join(context.directory, "oversized")
    {:ok, file} = File.open(path, [:write, :binary, :raw])
    {:ok, 67_108_864} = :file.position(file, 67_108_864)
    :ok = :file.write(file, <<0>>)
    :ok = File.close(file)
    File.chmod!(path, 0o700)

    assert {:error, %Error{code: :transport_unavailable}} =
             Executable.verify(path, @digest, deadline())
  end

  test "WBL-B01 hashing spans chunks and detects later deployment replacement", context do
    bytes = :binary.copy(<<0, 255, 1>>, 65_536)
    {path, digest} = file(context, "large", bytes)
    assert {:ok, admitted} = Executable.verify(path, digest, deadline())
    assert admitted.bytes == byte_size(bytes)
    File.write!(path, "changed deployment")

    assert {:error, %Error{code: :incompatible_backend}} =
             Executable.verify(path, digest, deadline())
  end

  test "WBL-B01 original deadline equality and malformed selectors fail before file lookup" do
    assert {:error, %Error{code: :timeout, field: :executable}} =
             Executable.verify("/missing/file", @digest, System.monotonic_time(:millisecond))

    for invalid <- [nil, false, 1.5, 9_223_372_036_854_775_808, -9_223_372_036_854_775_809] do
      assert {:error, %Error{code: :invalid_options}} =
               Executable.verify("/missing/file", @digest, invalid)
    end

    assert {:error, %Error{code: :invalid_options}} =
             Executable.verify("relative", @digest, deadline())

    assert {:error, %Error{code: :invalid_options}} =
             Executable.verify("/missing/file", "wrong", deadline())

    assert {:error, %Error{code: :timeout}} =
             Artifacts.verify(@selectors, System.monotonic_time(:millisecond))
  end

  defp file(context, name, bytes) do
    path = Path.join(context.directory, name)
    File.write!(path, bytes)
    File.chmod!(path, 0o700)
    {path, Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 5000
end
