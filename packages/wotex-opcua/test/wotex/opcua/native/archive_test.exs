defmodule Wotex.OPCUA.Native.ArchiveTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Native.Archive
  doctest Archive

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "wotex-opcua-native-archive-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "WOP-X02 verified archive bytes extract without altering an existing destination", %{
    dir: dir
  } do
    archive = Path.join(dir, "source.tar.gz")

    assert :ok =
             :erl_tar.create(String.to_charlist(archive), [{~c"sdk/value", "content"}], [
               :compressed
             ])

    source = identity(archive)
    destination = Path.join(dir, "extract")
    assert :ok = Archive.extract(archive, destination, source)
    assert File.read!(Path.join(destination, "sdk/value")) == "content"
    assert {:error, :destination_exists} = Archive.extract(archive, destination, source)
    assert File.read!(Path.join(destination, "sdk/value")) == "content"
  end

  test "WOP-X02 wrong digest or malformed tar performs no extraction", %{dir: dir} do
    archive = Path.join(dir, "source.tar.gz")
    File.write!(archive, "not a tar")
    destination = Path.join(dir, "extract")

    assert {:error, :source_digest_mismatch} =
             Archive.extract(archive, destination, %{root: "sdk", sha256: String.duplicate("0", 64)})

    assert {:error, :invalid_archive} = Archive.extract(archive, destination, identity(archive))
    refute File.exists?(destination)

    assert {:error, :archive_unreadable} =
             Archive.extract(archive <> ".missing", destination, identity(archive))
  end

  test "WOP-X02 archive traversal and foreign roots fail before creating the output", %{dir: dir} do
    for entry <- [
          ~c"sdk/../escape",
          ~c"another/value",
          ~c"/sdk/value"
        ] do
      archive = Path.join(dir, "source.tar.gz")
      :ok = :erl_tar.create(String.to_charlist(archive), [{entry, "content"}], [:compressed])

      assert {:error, :invalid_archive_entry} =
               Archive.extract(archive, Path.join(dir, "extract"), identity(archive))

      refute File.exists?(Path.join(dir, "extract"))
    end
  end

  test "WOP-X02 configuration failures do not touch a workspace", %{dir: dir} do
    archive = Path.join(dir, "source.tar.gz")
    File.write!(archive, "data")
    valid = identity(archive)

    for {path, dest, source} <- [
          {nil, dir, valid},
          {archive, nil, valid},
          {archive, dir, nil},
          {"relative", dir, valid},
          {archive, "relative", valid},
          {archive, dir, %{valid | root: "../bad"}},
          {archive, dir, %{valid | sha256: "bad"}}
        ] do
      assert {:error, :invalid_archive_options} = Archive.extract(path, dest, source)
    end
  end

  test "WOP-X02 metadata bounds reject ambiguous names and allocation excess" do
    valid = {~c"sdk/value", :regular, 1, 0, 0o644, 0, 0}
    assert :ok = Archive.validate_entries([valid], "sdk")

    assert :ok =
             Archive.validate_entries(
               [{~c"pax_global_header", :unknown, 52, 0, 0, 0, 0}, valid],
               "sdk"
             )

    assert {:error, :invalid_archive_entry} = Archive.validate_entries([valid, valid], "sdk")
    assert {:error, :invalid_archive_entry} = Archive.validate_entries([{:bad}], "sdk")
    assert {:error, :invalid_archive_entry} = Archive.validate_entries(nil, "sdk")
    assert {:error, :archive_expansion_limit} = Archive.validate_entries([], "sdk")
    assert {:error, :archive_expansion_limit} = Archive.validate_entries([valid], "..")

    assert {:error, :archive_expansion_limit} =
             Archive.validate_entries(List.duplicate(valid, 20_001), "sdk")

    assert {:error, :archive_expansion_limit} =
             Archive.validate_entries([put_elem(valid, 2, 67_108_865)], "sdk")

    assert {:error, :archive_expansion_limit} =
             Archive.validate_entries([{~c"sdk", :directory, 1, 0, 0o755, 0, 0}], "sdk")

    for changed <- [
          put_elem(valid, 1, :symlink),
          put_elem(valid, 1, :link),
          put_elem(valid, 4, 0o4644),
          put_elem(valid, 0, ~c"sdk\\value"),
          put_elem(valid, 0, ~c"sdk/a:b"),
          put_elem(valid, 0, ~c"sdk/../value")
        ] do
      assert {:error, :invalid_archive_entry} = Archive.validate_entries([changed], "sdk")
    end
  end

  test "WOP-X02 missing destination parent fails without modifying source", %{dir: dir} do
    archive = Path.join(dir, "source.tar.gz")
    :ok = :erl_tar.create(String.to_charlist(archive), [{~c"sdk/value", "content"}], [:compressed])

    assert {:error, :destination_unavailable} =
             Archive.extract(archive, Path.join(dir, "absent/extract"), identity(archive))

    assert File.regular?(archive)
  end

  test "WOP-X02 a bounded archive snapshot rejects excess before digest or extraction", %{dir: dir} do
    archive = Path.join(dir, "source.tar.gz")
    {:ok, file} = :file.open(String.to_charlist(archive), [:write, :raw, :binary])
    {:ok, _} = :file.position(file, 100 * 1024 * 1024)
    :ok = :file.write(file, <<0>>)
    :ok = :file.close(file)
    destination = Path.join(dir, "extract")

    assert {:error, :archive_limit} =
             Archive.extract(archive, destination, %{root: "sdk", sha256: String.duplicate("0", 64)})

    refute File.exists?(destination)
  end

  test "WOP-X02 malformed character lists and global-header-only input fail finitely" do
    assert {:error, :invalid_archive_entry} =
             Archive.validate_entries([{[-1], :regular, 1, 0, 0o644, 0, 0}], "sdk")

    assert {:error, :invalid_archive_entry} =
             Archive.validate_entries([{~c"pax_global_header", :unknown, 52, 0, 0, 0, 0}], "sdk")

    files =
      for i <- 1..9,
          do: {String.to_charlist("sdk/value#{i}"), :regular, 64 * 1024 * 1024, 0, 0o644, 0, 0}

    assert {:error, :archive_expansion_limit} = Archive.validate_entries(files, "sdk")
  end

  defp identity(archive) do
    %{root: "sdk", sha256: Base.encode16(:crypto.hash(:sha256, File.read!(archive)), case: :lower)}
  end
end
