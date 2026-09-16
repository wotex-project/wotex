defmodule Wotex.CoAP.Native.ArchiveTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.CoAP.Native.Archive

  @revision "7cf7465b784baded4de183290c547d582becfd28"
  @source_sha256 "d8ce60574b1ed60ab1ef5c8d656bdf1c4a28fff0a00e9cb9f2cce3772f9db8cd"

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-native-archive-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "WCO-N01 verified archive bytes extract once", %{root: root} do
    archive = Path.join(root, "source.tar.gz")

    :ok =
      :erl_tar.create(String.to_charlist(archive), [{~c"libcoap/value", "content"}], [:compressed])

    source = identity(archive)
    destination = Path.join(root, "extract")

    assert :ok = Archive.extract(archive, destination, source)
    assert File.read!(Path.join(destination, "libcoap/value")) == "content"
    assert {:error, :destination_exists} = Archive.extract(archive, destination, source)
    assert File.read!(Path.join(destination, "libcoap/value")) == "content"
  end

  test "WCO-N01 wrong digest, malformed input and missing source create no output", %{root: root} do
    archive = Path.join(root, "source.tar.gz")
    File.write!(archive, "not a tar")
    destination = Path.join(root, "extract")

    assert {:error, :source_digest_mismatch} =
             Archive.extract(archive, destination, %{
               root: "libcoap",
               sha256: String.duplicate("0", 64)
             })

    assert {:error, :invalid_archive} = Archive.extract(archive, destination, identity(archive))

    assert {:error, :archive_unreadable} =
             Archive.extract(archive <> ".missing", destination, identity(archive))

    refute File.exists?(destination)
  end

  test "WCO-N01 rejects traversal, foreign roots and absolute archive members", %{root: root} do
    for entry <- [~c"libcoap/../escape", ~c"another/value", ~c"/libcoap/value"] do
      archive = Path.join(root, "source.tar.gz")
      :ok = :erl_tar.create(String.to_charlist(archive), [{entry, "content"}], [:compressed])

      assert {:error, :invalid_archive_entry} =
               Archive.extract(archive, Path.join(root, "extract"), identity(archive))

      refute File.exists?(Path.join(root, "extract"))
    end
  end

  test "WCO-N01 rejects malformed extraction options before mutation", %{root: root} do
    archive = Path.join(root, "source.tar.gz")
    File.write!(archive, "data")
    valid = identity(archive)

    for {path, destination, source} <- [
          {nil, root, valid},
          {archive, nil, valid},
          {archive, root, nil},
          {"relative", root, valid},
          {archive, "relative", valid},
          {archive, root, %{valid | root: "../bad"}},
          {archive, root, %{valid | sha256: "bad"}}
        ] do
      assert {:error, :invalid_archive_options} = Archive.extract(path, destination, source)
    end
  end

  test "WCO-N01 metadata bounds reject links, duplicate paths and expansion", %{root: root} do
    valid = {~c"libcoap/value", :regular, 1, 0, 0o644, 0, 0}
    assert :ok = Archive.validate_entries([valid], "libcoap")

    assert :ok =
             Archive.validate_entries(
               [{~c"pax_global_header", :unknown, 52, 0, 0, 0, 0}, valid],
               "libcoap"
             )

    assert {:error, :invalid_archive_entry} = Archive.validate_entries([valid, valid], "libcoap")
    assert {:error, :invalid_archive_entry} = Archive.validate_entries([{:bad}], "libcoap")
    assert {:error, :invalid_archive_entry} = Archive.validate_entries(nil, "libcoap")
    assert {:error, :archive_expansion_limit} = Archive.validate_entries([], "libcoap")
    assert {:error, :archive_expansion_limit} = Archive.validate_entries([valid], "..")

    assert {:error, :archive_expansion_limit} =
             Archive.validate_entries(List.duplicate(valid, 20_001), "libcoap")

    assert {:error, :archive_expansion_limit} =
             Archive.validate_entries([put_elem(valid, 2, 33_554_433)], "libcoap")

    files =
      for index <- 1..5,
          do:
            {String.to_charlist("libcoap/value#{index}"), :regular, 32 * 1024 * 1024, 0, 0o644, 0,
             0}

    assert {:error, :archive_expansion_limit} = Archive.validate_entries(files, "libcoap")

    for changed <- [
          put_elem(valid, 1, :symlink),
          put_elem(valid, 1, :link),
          put_elem(valid, 4, 0o4644),
          put_elem(valid, 0, ~c"libcoap\\value"),
          put_elem(valid, 0, ~c"libcoap/a:b"),
          put_elem(valid, 0, ~c"libcoap/../value"),
          {~c"libcoap", :directory, 1, 0, 0o755, 0, 0}
        ] do
      assert {:error, expected} = Archive.validate_entries([changed], "libcoap")
      assert expected in [:invalid_archive_entry, :archive_expansion_limit]
    end

    archive = Path.join(root, "source.tar.gz")
    create_archive(archive)

    assert {:error, :destination_unavailable} =
             Archive.extract(archive, Path.join(root, "missing/extract"), identity(archive))
  end

  test "WCO-N01 archive byte ceiling applies before parsing", %{root: root} do
    archive = Path.join(root, "source.tar.gz")
    {:ok, file} = :file.open(String.to_charlist(archive), [:write, :raw, :binary])
    {:ok, _} = :file.position(file, 4 * 1024 * 1024)
    :ok = :file.write(file, <<0>>)
    :ok = :file.close(file)

    assert {:error, :archive_limit} =
             Archive.extract(archive, Path.join(root, "extract"), %{
               root: "libcoap",
               sha256: String.duplicate("0", 64)
             })
  end

  test "WCO-N01 extraction failure removes only the new destination", %{root: root} do
    archive = Path.join(root, "source.tar.gz")

    :ok =
      :erl_tar.create(
        String.to_charlist(archive),
        [{~c"libcoap/parent", "file"}, {~c"libcoap/parent/child", "blocked"}],
        [:compressed]
      )

    destination = Path.join(root, "extract")
    assert {:error, :extraction_failed} = Archive.extract(archive, destination, identity(archive))
    refute File.exists?(destination)
    assert File.regular?(archive)
  end

  test "WCO-N01 malformed names and metadata-only archives fail finitely" do
    assert {:error, :invalid_archive_entry} =
             Archive.validate_entries([{[-1], :regular, 1, 0, 0o644, 0, 0}], "libcoap")

    assert {:error, :invalid_archive_entry} =
             Archive.validate_entries(
               [{~c"pax_global_header", :unknown, 52, 0, 0, 0, 0}],
               "libcoap"
             )
  end

  test "WCO-N01 the digest-bound upstream links remain inside the reviewed root", %{root: root} do
    archive_root = "libcoap-#{@revision}"

    regular = fn path ->
      {String.to_charlist("#{archive_root}/#{path}"), :regular, 1, 0, 0o644, 0, 0}
    end

    link = fn path ->
      {String.to_charlist("#{archive_root}/#{path}"), :symlink, 0, 0, 0o777, 0, 0}
    end

    entries = [
      regular.("README.md"),
      regular.("coap_config.h.contiki"),
      link.("README"),
      link.("examples/contiki/coap_config.h")
    ]

    assert :ok = Archive.validate_entries(entries, archive_root, @source_sha256)
    assert {:error, :invalid_archive_entry} = Archive.validate_entries(entries, archive_root)
    assert {:error, :invalid_archive_entry} = Archive.validate_entries(nil, nil, nil)

    destination = Path.join(root, "valid-links")
    extracted = Path.join(destination, archive_root)
    File.mkdir_p!(Path.join(extracted, "examples/contiki"))
    File.write!(Path.join(extracted, "README.md"), "readme")
    File.write!(Path.join(extracted, "coap_config.h.contiki"), "config")
    File.ln_s!("README.md", Path.join(extracted, "README"))

    File.ln_s!(
      "../../coap_config.h.contiki",
      Path.join(extracted, "examples/contiki/coap_config.h")
    )

    assert :ok = Archive.verify_links(destination, archive_root, @source_sha256)
    assert :ok = Archive.verify_links(destination, archive_root, String.duplicate("0", 64))

    invalid = Path.join(root, "invalid-links")
    invalid_root = Path.join(invalid, archive_root)
    File.mkdir_p!(Path.join(invalid_root, "examples/contiki"))
    File.write!(Path.join(invalid_root, "README.md"), "readme")
    File.write!(Path.join(invalid_root, "coap_config.h.contiki"), "config")
    File.ln_s!("missing", Path.join(invalid_root, "README"))

    File.ln_s!(
      "../../coap_config.h.contiki",
      Path.join(invalid_root, "examples/contiki/coap_config.h")
    )

    assert {:error, :invalid_archive_entry} =
             Archive.verify_links(invalid, archive_root, @source_sha256)

    refute File.exists?(invalid)
  end

  defp create_archive(path) do
    :ok = :erl_tar.create(String.to_charlist(path), [{~c"libcoap/value", "content"}], [:compressed])
    path
  end

  defp identity(archive) do
    %{
      root: "libcoap",
      sha256: Base.encode16(:crypto.hash(:sha256, File.read!(archive)), case: :lower)
    }
  end
end
