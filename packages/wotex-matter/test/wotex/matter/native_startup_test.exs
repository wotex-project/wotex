defmodule Wotex.Matter.NativeStartupTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.{Error, Native, Subscription}
  alias Wotex.Matter.Native.{Connection, OneshotHandle}

  @ready ~s({"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"})
  @opened ~s({"version":1,"id":"1","ok":true,"result":{"lifecycle":"persistent","fabric_id":1,"controller_node_id":2,"vendor_id":65521}})

  test "a native host that exits before ready is a closed transport" do
    assert {:error, %Error{code: :transport_closed}} =
             Native.connect(options(host("exit 0")))
  end

  test "an oversized line before ready is bounded as a response limit" do
    oversized = host("head -c 140000 /dev/zero | tr '\\000' a\nIFS= read -r eof")

    assert {:error, %Error{code: :response_limit}} = Native.connect(options(oversized))
  end

  test "a digest mismatch starts no native controller" do
    marker = temporary_path("digest-marker")
    executable = host("printf started > #{marker}")
    options = Keyword.put(options(executable), :executable_sha256, String.duplicate("0", 64))

    assert {:error, %Error{code: :incompatible_backend, field: :executable}} =
             Native.connect(options)

    refute File.exists?(marker)
  end

  test "an owner lost before ready closes startup without a handshake" do
    {owner, monitor} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    silent = host("IFS= read -r line")

    assert {:error, %Error{code: :owner_closed}} =
             Connection.start(owner, %{executable: silent, timeout: 5_000})
  end

  test "output after the close acknowledgment fails a cooperative disconnect" do
    chatty =
      host("""
      printf '%s\\n' '#{@ready}'
      IFS= read -r flow
      IFS= read -r open
      printf '%s\\n' '#{@opened}'
      IFS= read -r close
      printf '%s\\n' '{"version":1,"id":"2","ok":true,"result":null}'
      printf '%s\\n' 'unframed'
      IFS= read -r eof
      """)

    assert {:ok, handle} = Native.connect(options(chatty))
    monitor = Process.monitor(handle.pid)

    assert {:error, %Error{code: :invalid_frame}} = Native.disconnect(handle)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
  end

  test "a one-shot handle neither subscribes nor unsubscribes" do
    options =
      host("exit 1")
      |> options()
      |> Keyword.merge(lifecycle: :oneshot, storage_mode: :open_existing, authority: :stored)

    assert {:ok, %OneshotHandle{} = handle} = Native.connect(options)
    subscription = %Subscription{pid: self(), reference: make_ref(), generation: 1}

    assert {:error, %Error{code: :not_supported}} =
             Native.subscribe_acknowledged(handle, %{}, self(), 1_000)

    assert {:error, %Error{code: :not_supported}} =
             Native.unsubscribe(handle, subscription, 1_000)
  end

  defp host(body) do
    path = temporary_path("host")
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o700)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp options(executable) do
    paa = temporary_path("paa")
    File.mkdir_p!(paa)
    on_exit(fn -> File.rm_rf(paa) end)

    [
      executable: executable,
      executable_sha256: digest(executable),
      lifecycle: :persistent,
      storage_path: temporary_path("store"),
      storage_mode: :create_new,
      authority: :generate_root,
      vendor_id: 65_521,
      fabric_id: 1,
      controller_node_id: 2,
      paa_trust_store: paa,
      timeout: 5_000
    ]
  end

  defp digest(path),
    do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  defp temporary_path(suffix) do
    Path.join(
      System.tmp_dir!(),
      "wotex-matter-startup-#{System.unique_integer([:positive])}-#{suffix}"
    )
  end
end
