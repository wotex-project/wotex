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

    for message <- [
          %{type: :read},
          %{type: :read_paths, paths: []},
          %{type: :read_paths, paths: [false]},
          %{type: :read_paths, paths: [%{fabric_id: 1}, %{fabric_id: 2}]}
        ] do
      assert {:error, %Error{code: :invalid_request, effect: :none}} =
               Native.request(handle, message, 1_000)
    end

    for timeout <- [0, 60_001, :infinity] do
      assert {:error, %Error{code: :invalid_handle}} = Native.request(handle, @read, timeout)
      assert {:error, %Error{code: :invalid_handle}} = Native.health(handle, timeout)
    end

    assert {:error, %Error{code: :invalid_handle}} = Native.unsubscribe(handle, nil, 1_000)
    assert {:error, %Error{code: :invalid_handle}} = Native.subscribe(handle, %{}, nil, 1_000)

    assert File.read!(audit) == initial
    assert :ok = Native.disconnect(handle)
  end

  test "WMA-C03 a foreign generation cannot use or close the live controller" do
    audit = temporary_path("generation-requests")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))
    foreign = %{handle | generation: String.duplicate("0", 32)}
    initial = File.read!(audit)

    assert {:error, %Error{code: :invalid_handle}} = Native.request(foreign, @read, 1_000)
    assert {:error, %Error{code: :invalid_handle}} = Native.health(foreign)
    assert {:error, %Error{code: :invalid_handle}} = Native.disconnect(foreign)

    assert {:error, %Error{code: :invalid_handle}} =
             Native.Connection.invalidate(foreign.pid, foreign.generation)

    assert File.read!(audit) == initial
    assert Process.alive?(handle.pid)
    assert {:ok, %{"status" => "ready"}} = Native.health(handle)
    assert :ok = Native.disconnect(handle)

    for invalid <- [nil, false, %{}, %{handle | pid: nil}] do
      assert {:error, %Error{code: :invalid_handle}} = Native.health(invalid)
      assert {:error, %Error{code: :invalid_handle}} = Native.request(invalid, @read, 1_000)
      assert :ok = Native.disconnect(invalid)
    end
  end

  test "WMA-C05 native subscription admission rejects invalid fields without opening a stream" do
    audit = temporary_path("subscription-admission")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))
    initial = File.read!(audit)
    path = Map.delete(@read, :type)

    request = %{
      kind: :attribute,
      paths: [path],
      min_interval_s: 0,
      max_interval_s: 1,
      resubscribe: false,
      queue_limit: 1
    }

    for {key, value} <- [
          {:kind, :unknown},
          {:paths, []},
          {:paths, [path, path]},
          {:paths, [nil]},
          {:paths, [%{path | node_id: 0}]},
          {:paths, [%{path | fabric_id: 2}]},
          {:paths, [%{path | cluster: 0x7FFF}]},
          {:min_interval_s, -1},
          {:max_interval_s, 0},
          {:resubscribe, 0},
          {:queue_limit, 0},
          {:queue_limit, 10_001},
          {:extra, true}
        ] do
      assert {:error, %Error{effect: :none}} =
               Native.subscribe(handle, Map.put(request, key, value), self(), 1_000)
    end

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
          Keyword.put(valid, :storage_path, nil),
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

    for mode <- ["bad_ready", "duplicate_ready", "foreign_id", "stdout_log"] do
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

  test "WMA-C07 an open reply must match the explicitly requested controller identity" do
    for mode <- [
          "wrong_open_fabric",
          "wrong_open_node",
          "wrong_open_vendor",
          "wrong_open_lifecycle",
          "extra_open_field",
          "null_open"
        ] do
      assert {:error, %Error{code: :invalid_controller_identity}} =
               Native.connect(options(fixture(mode)))
    end
  end

  test "WMA-C07 malformed replies retire the controller generation" do
    for {mode, code} <- [
          {"malformed_reply", :invalid_frame},
          {"oversized_reply", :response_limit},
          {"request_eof", :transport_closed}
        ] do
      assert {:ok, handle} = Native.connect(options(fixture(mode)))
      monitor = Process.monitor(handle.pid)
      assert {:error, %Error{code: ^code}} = Native.health(handle)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
      assert {:error, %Error{code: :transport_closed}} = Native.health(handle)
    end
  end

  test "WMA-C03 owner death interrupts an in-flight native request" do
    audit = temporary_path("inflight-owner")
    executable = fixture("silent_request", audit)
    parent = self()

    owner =
      spawn(fn ->
        {:ok, handle} = Native.connect(options(executable))
        send(parent, {:handle, handle})
        send(parent, {:late_response, Native.health(handle, 60_000)})
      end)

    assert_receive {:handle, handle}, 2_000
    assert request_recorded?(audit, 100)
    monitor = Process.monitor(handle.pid)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
    refute_receive {:late_response, _}
  end

  test "WMA-C04 a broken reply after mutation submission has unknown effect" do
    for message <- [
          Map.merge(@read, %{
            type: :write,
            member: 18,
            value: %{tag: :anonymous, type: :i16, value: 2000}
          }),
          Map.merge(@read, %{
            type: :invoke,
            cluster: 6,
            member: 1,
            value: %{tag: :anonymous, type: :structure, value: []}
          })
        ] do
      assert {:ok, handle} = Native.connect(options(fixture("malformed_reply")))

      assert {:error,
              %Error{code: :invalid_frame, effect: :unknown, class: :permanent, retryable: false}} =
               Native.request(handle, message, 1_000)

      assert :ok = Native.disconnect(handle)

      assert {:ok, malformed} = Native.connect(options(fixture("malformed_result")))
      monitor = Process.monitor(malformed.pid)

      assert {:error,
              %Error{code: :invalid_frame, effect: :unknown, class: :permanent, retryable: false}} =
               Native.request(malformed, message, 1_000)

      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000

      assert {:ok, refused} = Native.connect(options(fixture("native_timeout")))

      assert {:error, %Error{code: :timeout, effect: :none}} =
               Native.request(refused, message, 1_000)

      assert :ok = Native.disconnect(refused)
    end
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
      case mode do
        "bad_ready" ->
          ~s({"version":1,"event":"ready","backend":"matter-native","revision":"wrong"})
        "duplicate_ready" ->
          ~s({"version":99,"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"})
        _ ->
          ~s({"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"})
      end

    IO.puts(ready)
    read.()
    read.()

    open_id = if mode == "foreign_id", do: "99", else: "1"
    open_result = ~s({"lifecycle":"persistent","fabric_id":1,"controller_node_id":2,"vendor_id":65521})
    open_result = case mode do
      "wrong_open_fabric" -> String.replace(open_result, ~s("fabric_id":1), ~s("fabric_id":2))
      "wrong_open_node" -> String.replace(open_result, ~s("controller_node_id":2), ~s("controller_node_id":3))
      "wrong_open_vendor" -> String.replace(open_result, ~s("vendor_id":65521), ~s("vendor_id":65522))
      "wrong_open_lifecycle" -> String.replace(open_result, "persistent", "oneshot")
      "extra_open_field" -> String.replace(open_result, "}", ~s(,"extra":true}))
      "null_open" -> "null"
      _ -> open_result
    end
    IO.puts(~s({"version":1,"id":"\#{open_id}","ok":true,"result":\#{open_result}}))

    loop = fn loop ->
      line = read.()
      [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)

      cond do
        mode == "malformed_reply" ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":null,"result":42}))
          loop.(loop)

        mode == "oversized_reply" ->
          IO.puts(String.duplicate("x", 131072))
          loop.(loop)

        mode == "request_eof" ->
          System.halt(78)

        mode == "silent_request" ->
          loop.(loop)

        mode == "native_timeout" ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":false,"error":{"code":"interaction_timeout","effect":"none"}}))
          loop.(loop)

        mode == "malformed_result" ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":false}))
          loop.(loop)

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

  defp request_recorded?(_, 0), do: false

  defp request_recorded?(audit, attempts) do
    if File.read!(audit) =~ ~s("operation":"health") do
      true
    else
      Process.sleep(10)
      request_recorded?(audit, attempts - 1)
    end
  end

  defp temporary_path(suffix) do
    Path.join(
      System.tmp_dir!(),
      "wotex-matter-p03-#{System.unique_integer([:positive])}-#{suffix}"
    )
  end
end
