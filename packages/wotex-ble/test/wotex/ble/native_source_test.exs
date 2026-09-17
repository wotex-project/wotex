defmodule Wotex.BLE.NativeSourceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.BLE.Native.Source

  @native Path.expand("../../../priv/bluez/native", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "wotex-ble-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "WBL-B01 packaged libdbus pin has exact fields and a pinned HTTPS release URL", %{
    root: root
  } do
    assert {:ok, pin} = Source.pin(@native, "libdbus")

    assert pin == %{
             "name" => "libdbus",
             "version" => "1.16.2",
             "url" => "https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz",
             "sha256" => "0ba2a1a4b16afe7bceb2c07e9ce99a8c2c3508e5dec290dbb643384bd6beb7e2",
             "root" => "dbus-1.16.2",
             "license" => "AFL-2.1 OR GPL-2.0-or-later",
             "license_path" => "COPYING"
           }

    assert {:error, :invalid_native_pins} = Source.pin(@native, "unknown")
    assert {:error, :invalid_native_pins} = Source.pin(root, "libdbus")
    assert {:error, :invalid_native_pins} = Source.pin(:native, "libdbus")

    for changed <- [
          Map.put(pin, "url", "http://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz"),
          Map.put(pin, "url", "https://example.test/dbus-1.16.2.tar.xz"),
          Map.put(pin, "sha256", String.upcase(pin["sha256"])),
          Map.put(pin, "root", "../dbus"),
          Map.put(pin, "extra", "field"),
          Map.delete(pin, "license")
        ] do
      write_pins(root, [changed])
      assert {:error, :invalid_native_pins} = Source.pin(root, "libdbus")
      assert {:error, :invalid_source_download} = Source.fetch(changed, Path.join(root, "a"))
    end

    existing = Path.join(root, "existing")
    File.write!(existing, "present")
    assert {:error, :invalid_source_download} = Source.fetch(pin, existing)
    assert File.read!(existing) == "present"

    write_pins(root, [pin, pin])
    assert {:error, :invalid_native_pins} = Source.pin(root, "libdbus")
    File.write!(Path.join(root, "dependencies.json"), "{")
    assert {:error, :invalid_native_pins} = Source.pin(root, "libdbus")
    assert {:error, :invalid_source_download} = Source.fetch(:pin, Path.join(root, "a"))
  end

  test "WBL-B01 digests and tree hashes admit only regular files", %{root: root} do
    tree = Path.join(root, "tree")
    File.mkdir_p!(Path.join(tree, "nested"))
    File.write!(Path.join(tree, "b"), "second")
    File.write!(Path.join(tree, "nested/a"), "first")

    assert {:ok, hashes} = Source.file_hashes(tree)
    assert hashes == %{"b" => sha256("second"), "nested/a" => sha256("first")}
    assert {:ok, digest} = Source.tree_digest(tree)
    assert {:ok, ^digest} = Source.tree_digest(tree)
    File.write!(Path.join(tree, "b"), "changed")
    refute {:ok, digest} == Source.tree_digest(tree)

    assert {:error, :invalid_source_file} = Source.digest(tree)
    assert {:error, :invalid_source_file} = Source.digest(:path)
    assert {:error, :invalid_source_tree} = Source.file_hashes(Path.join(tree, "b"))
    assert {:error, :invalid_source_tree} = Source.file_hashes(:tree)
    File.chmod!(Path.join(tree, "b"), 0o000)

    try do
      assert {:error, :invalid_source_tree} = Source.file_hashes(tree)
    after
      File.chmod!(Path.join(tree, "b"), 0o600)
    end

    File.chmod!(Path.join(tree, "nested"), 0o000)

    try do
      assert {:error, :invalid_source_tree} = Source.file_hashes(tree)
    after
      File.chmod!(Path.join(tree, "nested"), 0o700)
    end

    File.ln_s!("b", Path.join(tree, "link"))
    assert {:error, :invalid_source_file} = Source.digest(Path.join(tree, "link"))
    assert {:error, :invalid_source_tree} = Source.tree_digest(tree)
  end

  test "WBL-B01 archives admit only the finite pinned root tree", %{root: root} do
    input = Path.join(root, "input")
    File.mkdir_p!(Path.join(input, "dbus-1.16.2/dbus"))
    File.write!(Path.join(input, "dbus-1.16.2/dbus/dbus.h"), "header")
    File.write!(Path.join(input, "dbus-1.16.2/configure"), "run")
    File.chmod!(Path.join(input, "dbus-1.16.2/configure"), 0o755)
    archive = Path.join(root, "dbus.tar")
    tar!(archive, input, ["dbus-1.16.2"])

    assert {:ok, entries} = Source.validate_archive(archive, "dbus-1.16.2")

    assert {"dbus-1.16.2/dbus/dbus.h", :regular, _} =
             List.keyfind(entries, "dbus-1.16.2/dbus/dbus.h", 0)

    assert {:error, :invalid_source_archive} = Source.validate_archive(archive, "other")
    assert {:error, :invalid_source_archive} = Source.validate_archive(root, "dbus-1.16.2")
    assert {:error, :invalid_source_archive} = Source.validate_archive(:archive, "dbus-1.16.2")

    destination = Path.join(root, "sources")
    assert :ok = Source.extract(archive, destination, "dbus-1.16.2")
    assert File.read!(Path.join(destination, "dbus-1.16.2/dbus/dbus.h")) == "header"
    assert mode(Path.join(destination, "dbus-1.16.2/configure")) == 0o700
    assert mode(Path.join(destination, "dbus-1.16.2/dbus/dbus.h")) == 0o600
    assert mode(Path.join(destination, "dbus-1.16.2")) == 0o700
    assert {:error, :invalid_source_archive} = Source.extract(archive, destination, "dbus-1.16.2")
    assert {:error, :invalid_source_archive} = Source.extract(archive, "relative", "dbus-1.16.2")
    assert {:error, :invalid_source_archive} = Source.extract(archive, :destination, "dbus-1.16.2")

    File.ln_s!(Path.join(root, "outside"), Path.join(root, "linked-destination"))

    assert {:error, :invalid_source_archive} =
             Source.extract(archive, Path.join(root, "linked-destination"), "dbus-1.16.2")

    File.ln_s!("dbus/dbus.h", Path.join(input, "dbus-1.16.2/link"))
    linked = Path.join(root, "linked.tar")
    tar!(linked, input, ["dbus-1.16.2"])
    assert {:error, :invalid_source_archive} = Source.validate_archive(linked, "dbus-1.16.2")

    File.rm!(Path.join(input, "dbus-1.16.2/link"))
    File.mkdir_p!(Path.join(input, "other"))
    File.write!(Path.join(input, "other/file"), "outside root")
    mixed = Path.join(root, "mixed.tar")
    tar!(mixed, input, ["dbus-1.16.2", "other"])
    assert {:error, :invalid_source_archive} = Source.validate_archive(mixed, "dbus-1.16.2")
    refute File.exists?(Path.join(root, "mixed-output"))
  end

  @tag :capture_log
  test "WBL-B01 verified HTTPS transfer checks trust, status, digest, size and deadline", %{
    root: root
  } do
    %{server: server, client: client} = tls()
    body = :binary.copy("dbus", 1024)
    digest = sha256(body)

    url = serve(server, fn socket -> respond(socket, 200, body) end)
    target = Path.join(root, "archive.tar.xz")
    assert :ok = Source.transfer(url, target, digest, cacerts: client)
    assert File.read!(target) == body
    refute File.exists?(target <> ".download")

    assert {:error, :invalid_source_download} =
             Source.transfer(url, target, digest, cacerts: client)

    url = serve(server, fn socket -> respond(socket, 200, body) end)
    target = Path.join(root, "mismatch")

    assert {:error, :source_hash_mismatch} =
             Source.transfer(url, target, String.duplicate("0", 64), cacerts: client)

    refute File.exists?(target) or File.exists?(target <> ".download")

    url = serve(server, fn socket -> respond(socket, 404, "missing") end)
    target = Path.join(root, "missing")

    assert {:error, :invalid_source_download} =
             Source.transfer(url, target, digest, cacerts: client)

    refute File.exists?(target <> ".download")

    url = serve(server, fn socket -> respond(socket, 200, body) end)
    target = Path.join(root, "limit")

    assert {:error, :source_download_limit} =
             Source.transfer(url, target, digest, cacerts: client, bytes: 1024)

    refute File.exists?(target <> ".download")

    url =
      serve(server, fn socket ->
        :ok = :ssl.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 10\r\n\r\nabc")
        Process.sleep(1000)
      end)

    target = Path.join(root, "slow")

    assert {:error, :source_download_timeout} =
             Source.transfer(url, target, digest, cacerts: client, timeout_ms: 200)

    url = serve(server, fn socket -> respond(socket, 200, body) end)
    target = Path.join(root, "untrusted")
    other = tls().client
    assert {:error, :invalid_source_download} = Source.transfer(url, target, digest, cacerts: other)

    assert {:error, :invalid_source_download} =
             Source.transfer("http://localhost/", Path.join(root, "plain"), digest, cacerts: client)

    assert {:error, :invalid_source_download} =
             Source.transfer(url, "relative", digest, cacerts: client)

    assert {:error, :invalid_source_download} =
             Source.transfer("https://[bad", Path.join(root, "malformed"), digest, cacerts: client)

    assert {:error, :invalid_source_download} =
             Source.transfer(url, Path.join(root, "digest"), "ABC", cacerts: client)
  end

  defp write_pins(root, downloads) do
    File.write!(
      Path.join(root, "dependencies.json"),
      Jason.encode!(%{"schema" => "wotex.native-sources", "version" => 1, "downloads" => downloads})
    )
  end

  defp tar!(archive, cwd, names) do
    files = Enum.map(names, &{String.to_charlist(&1), String.to_charlist(Path.join(cwd, &1))})
    :ok = :erl_tar.create(String.to_charlist(archive), files)
  end

  defp mode(path), do: Bitwise.band(File.lstat!(path).mode, 0o777)

  defp sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp tls do
    extension = {:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}
    key = {:rsa, 2048, 65_537}

    data =
      :public_key.pkix_test_data(%{
        server_chain: %{
          root: [key: key],
          intermediates: [],
          peer: [key: key, extensions: [extension]]
        },
        client_chain: %{root: [key: key], intermediates: [], peer: [key: key]}
      })

    %{server: data.server_config, client: Keyword.fetch!(data.client_config, :cacerts)}
  end

  defp serve(server, respond) do
    {:ok, listen} = :ssl.listen(0, server ++ [active: false, reuseaddr: true, mode: :binary])
    {:ok, {_, port}} = :ssl.sockname(listen)

    pid =
      spawn(fn ->
        with {:ok, transport} <- :ssl.transport_accept(listen, 5000),
             {:ok, socket} <- :ssl.handshake(transport, 5000),
             {:ok, _} <- request(socket, <<>>) do
          respond.(socket)
          :ssl.close(socket)
        end

        :ssl.close(listen)
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    "https://localhost:#{port}/dbus-1.16.2.tar.xz"
  end

  defp request(socket, bytes) do
    if String.contains?(bytes, "\r\n\r\n") do
      {:ok, bytes}
    else
      with {:ok, more} <- :ssl.recv(socket, 0, 5000), do: request(socket, bytes <> more)
    end
  end

  defp respond(socket, status, body) do
    :ssl.send(socket, [
      "HTTP/1.1 #{status} Status\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
      body
    ])
  end
end
