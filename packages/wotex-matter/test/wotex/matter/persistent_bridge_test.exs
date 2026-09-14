defmodule Wotex.Matter.PersistentBridgeTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter
  alias Wotex.Matter.{Error, Native}

  @read %{
    type: :read,
    fabric_id: 1,
    node_id: 2,
    endpoint: 1,
    cluster: 513,
    member: 0
  }

  test "persistent owner validates native identity, correlates calls and closes explicitly" do
    fixture = fixture("valid")
    options = options(fixture)

    assert {:ok, session} = Matter.connect([client: Native] ++ options)
    refute inspect(session) =~ "session_generation"
    refute inspect(session.handle) =~ inspect(session.handle.pid)

    assert {:ok, %{"status" => "ready", "fabric_id" => 1}} =
             Native.health(session.handle)

    assert {:error, %Error{code: :not_supported, effect: :none}} =
             Matter.send(session, @read)

    assert :ok = Matter.disconnect(session)
    refute Process.alive?(session.handle.pid)
    assert :ok = Matter.disconnect(session)
  end

  test "wrong fabric is rejected before the native request boundary" do
    audit = temporary_path("requests")
    fixture = fixture("valid", audit)
    assert {:ok, handle} = Native.connect(options(fixture))
    initial = File.read!(audit)

    assert {:error, %Error{code: :fabric_mismatch, effect: :none}} =
             Native.request(handle, %{@read | fabric_id: 2}, 1_000)

    assert File.read!(audit) == initial
    assert :ok = Native.disconnect(handle)
  end

  test "malformed operation types fail before native serialization" do
    audit = temporary_path("malformed-requests")
    fixture = fixture("valid", audit)
    assert {:ok, handle} = Native.connect(options(fixture))
    initial = File.read!(audit)

    assert {:error, %Error{code: :invalid_request, effect: :none}} =
             Native.request(handle, %{type: "read", fabric_id: 1}, 1_000)

    assert {:error, %Error{code: :invalid_request, effect: :none}} =
             Native.request(handle, %{fabric_id: 1}, 1_000)

    assert {:error, %Error{code: :invalid_request, effect: :none}} =
             Native.request(handle, %{"node_id" => 2, type: :read, fabric_id: 1}, 1_000)

    assert {:error, %Error{code: :invalid_request, effect: :none}} =
             Native.request(handle, :not_a_map, 1_000)

    assert File.read!(audit) == initial
    assert :ok = Native.disconnect(handle)
  end

  test "invalid options and startup frames fail without returning a handle" do
    valid = options(fixture("valid"))

    for options <- [
          :invalid,
          [],
          Keyword.put(valid, :lifecycle, :oneshot),
          Keyword.put(valid, :storage_path, "relative"),
          Keyword.put(valid, :storage_mode, :unknown),
          Keyword.put(valid, :authority, :external),
          Keyword.put(valid, :vendor_id, 0),
          Keyword.put(valid, :fabric_id, 0),
          Keyword.put(valid, :controller_node_id, 0),
          Keyword.put(valid, :paa_trust_store, temporary_path("missing-paa")),
          Keyword.put(valid, :executable, temporary_path("missing-host")),
          [{:vendor_id, 1} | valid]
        ] do
      assert {:error, %Error{}} = Native.connect(options)
    end

    for mode <- ["bad_ready", "foreign_id", "stdout_log"] do
      assert {:error, %Error{}} = Native.connect(options(fixture(mode)))
    end

    assert {:ok, handle} = Native.connect(options(fixture("noisy_stderr")))
    assert :ok = Native.disconnect(handle)
  end

  test "the creating process owns connection and native process lifetime" do
    fixture = fixture("valid")
    parent = self()

    owner =
      spawn(fn ->
        {:ok, handle} = Native.connect(options(fixture))
        send(parent, {:handle, handle})
        Process.sleep(:infinity)
      end)

    assert_receive {:handle, handle}, 2_000
    monitor = Process.monitor(handle.pid)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 2_000
  end

  defp options(executable) do
    paa = temporary_path("paa")
    File.mkdir_p!(paa)

    [
      executable: executable,
      lifecycle: :persistent,
      storage_path: temporary_path("store"),
      storage_mode: :create_new,
      authority: :generate_root,
      vendor_id: 65_521,
      fabric_id: 1,
      controller_node_id: 2,
      paa_trust_store: paa,
      timeout: 3_000
    ]
  end

  defp fixture(mode, audit \\ nil) do
    path = temporary_path("#{mode}-host")
    audit = audit || temporary_path("#{mode}-audit")

    script = """
    #!/usr/bin/env elixir
    mode = #{inspect(mode)}
    audit = #{inspect(audit)}
    record = fn line -> File.write!(audit, line, [:append]) end
    read = fn ->
      case IO.read(:stdio, :line) do
        :eof -> System.halt(0)
        {:error, _} -> System.halt(1)
        line -> record.(line); line
      end
    end

    if mode == "stdout_log" do
      IO.puts("unframed log")
      System.halt(0)
    end

    if mode == "noisy_stderr", do: IO.puts(:stderr, "native-log")

    ready =
      if mode == "bad_ready" do
        ~s({"version":1,"event":"ready","backend":"matter-native","revision":"wrong"})
      else
        ~s({"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"})
      end

    IO.puts(ready)
    read.()
    read.()

    open_id = if mode == "foreign_id", do: "99", else: "1"
    IO.puts(~s({"version":1,"id":"\#{open_id}","ok":true,"result":{"lifecycle":"persistent","fabric_id":1,"controller_node_id":2,"vendor_id":65521}}))

    loop = fn loop ->
      line = read.()
      [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)

      cond do
        String.contains?(line, ~s("operation":"close")) ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":null}))

        String.contains?(line, ~s("operation":"health")) ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":{"status":"ready","fabric_id":1}}))
          loop.(loop)

        true ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":false,"error":{"code":"not_supported"}}))
          loop.(loop)
      end
    end

    loop.(loop)
    """

    File.write!(path, script)
    File.chmod!(path, 0o700)

    on_exit(fn ->
      File.rm(path)
      File.rm(audit)
    end)

    path
  end

  defp temporary_path(suffix) do
    Path.join(
      System.tmp_dir!(),
      "wotex-matter-p03-#{System.unique_integer([:positive])}-#{suffix}"
    )
  end
end
