defmodule Wotex.CoAP.NativeConnectionTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.CoAP.{Error, Security}
  alias Wotex.CoAP.Native.Connection

  @revision "7cf7465b784baded4de183290c547d582becfd28"

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-native-connection-#{System.unique_integer([:positive])}"
      )

    store = Path.join(root, "context")
    executable = Path.join(root, "wotex-coap-oscore")
    manifest = Path.join(root, "native-manifest.json")
    File.mkdir_p!(store)
    File.write!(executable, helper_source())
    File.chmod!(executable, 0o700)
    File.write!(manifest, manifest(digest(executable)))

    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      store: store,
      executable: executable,
      manifest: manifest,
      options: options(executable, manifest, store)
    }
  end

  test "WCO-N02 launches the verified custody entry and completes exact ready/open/close",
       context do
    File.write!(Path.join(context.store, "mode"), "valid")

    assert {:ok, pid} = Connection.start(context.options)
    assert Process.alive?(pid)
    assert File.read!(Path.join(context.store, "arguments")) == "--custody\n#{context.store}"

    open =
      context.store
      |> Path.join("open.json")
      |> File.read!()
      |> Jason.decode!()

    assert open["version"] == 1
    assert open["id"] == "1"
    assert open["operation"] == "open"
    assert open["timeout_ms"] in 1..3_000
    assert open["parameters"]["host"] == "127.0.0.1"
    assert open["parameters"]["port"] == 5683
    assert open["parameters"]["generation"] in 1..0xFFFFFFFFFFFFFFFF
    assert open["parameters"]["security"]["mode"] == "oscore"
    assert open["parameters"]["security"]["master_secret"] == bytes(<<0::128>>)

    refute inspect(:sys.get_state(pid)) =~ Base.encode64(secret_canary())
    refute inspect(:sys.get_status(pid)) =~ Base.encode64(secret_canary())

    assert :ok = Connection.close(pid)
    refute Process.alive?(pid)
    assert :ok = Connection.close(pid)

    close =
      context.store
      |> Path.join("close.json")
      |> File.read!()
      |> Jason.decode!()

    assert close == %{
             "id" => "2",
             "operation" => "close",
             "parameters" => %{},
             "timeout_ms" => 350,
             "version" => 1
           }
  end

  test "WCO-N02 rejects malformed options and identity before acquiring a process", context do
    invalid = [
      Keyword.put(context.options, :host, "localhost"),
      Keyword.put(context.options, :host, <<255>>),
      Keyword.put(context.options, :host, nil),
      Keyword.put(context.options, :port, 0),
      Keyword.put(context.options, :timeout, :infinity),
      Keyword.put(context.options, :owner, :owner),
      Keyword.put(context.options, :security, nil),
      Keyword.put(context.options, :native_backend, %{}),
      [{:timeout, 1} | context.options],
      [{:unknown, true} | context.options]
    ]

    for options <- invalid do
      assert {:error, %Error{}} = Connection.start(options)
    end

    refute File.exists?(Path.join(context.store, "helper.pid"))
    assert {:error, %Error{code: :invalid_session}} = Connection.close(self())
  end

  test "WCO-N02 closes malformed ready and wrong or duplicate open responses", context do
    for {mode, expected} <- [
          {"wrong_ready", :native_protocol_error},
          {"duplicate_ready_key", :native_protocol_error},
          {"extra_ready", :native_protocol_error},
          {"wrong_open_id", :native_protocol_error},
          {"truncated", :native_protocol_error},
          {"oversize", :native_protocol_error},
          {"open_error", :context_store_locked}
        ] do
      File.write!(Path.join(context.store, "mode"), mode)
      File.rm(Path.join(context.store, "helper.pid"))

      assert {:error, %Error{code: ^expected}} = Connection.start(context.options), mode
      assert_helper_stopped(context.store, 1_000)
    end

    File.write!(Path.join(context.store, "mode"), "duplicate")
    assert {:ok, pid} = Connection.start(context.options)
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 accepts split frames and closes on native close errors", context do
    File.write!(Path.join(context.store, "mode"), "split")
    assert {:ok, pid} = Connection.start(context.options)
    assert :ok = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_error")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :busy}} = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_malformed")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_partial_exit")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_extra")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)
  end

  test "WCO-N02 reserves close control and releases pending callers during termination", context do
    File.write!(Path.join(context.store, "mode"), "close_silent")
    assert {:ok, pid} = Connection.start(context.options)
    closing = Task.async(fn -> Connection.close(pid) end)

    close_path = Path.join(context.store, "close.json")
    wait_for_file(close_path, System.monotonic_time(:millisecond) + 1_000)
    assert {:error, %Error{code: :busy}} = GenServer.call(pid, :close)
    assert {:error, %Error{code: :timeout}} = Task.await(closing, 1_000)
    assert :ok = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_silent")
    File.rm(close_path)
    assert {:ok, pid} = Connection.start(context.options)
    closing = Task.async(fn -> Connection.close(pid) end)
    wait_for_file(close_path, System.monotonic_time(:millisecond) + 1_000)
    assert :ok = GenServer.stop(pid, :shutdown, 1_000)
    assert {:error, %Error{code: :connection_closed}} = Task.await(closing, 1_000)
  end

  test "WCO-C03 WCO-N02 forces an exact helper that ignores graceful termination", context do
    File.write!(context.executable, stubborn_helper_source())
    File.chmod!(context.executable, 0o700)
    File.write!(context.manifest, manifest(digest(context.executable)))

    assert {:ok, pid} = Connection.start(context.options)
    started = System.monotonic_time(:millisecond)
    assert {:error, %Error{code: :timeout}} = Connection.close(pid)
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-C03 WCO-N02 bounds cleanup when the BEAM owner is suspended", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    :sys.suspend(pid)
    started = System.monotonic_time(:millisecond)
    assert {:error, %Error{code: :cleanup_timeout}} = Connection.close(pid)
    assert System.monotonic_time(:millisecond) - started < 1_100
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 closes idle generations on unsolicited output or helper exit", context do
    for mode <- ["unsolicited", "exit_after_open"] do
      File.write!(Path.join(context.store, "mode"), mode)
      assert {:ok, pid} = Connection.start(context.options)
      monitor = Process.monitor(pid)
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
      assert_helper_stopped(context.store, 1_000)
    end

    File.write!(Path.join(context.store, "mode"), "close_exit")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)
  end

  test "WCO-N02 monitors distinct configured owners and creators", context do
    configured_owner = spawn(fn -> Process.sleep(:infinity) end)
    options = Keyword.put(context.options, :owner, configured_owner)
    File.write!(Path.join(context.store, "mode"), "valid")
    parent = self()

    creator =
      spawn(fn ->
        send(parent, {:created_native, self(), Connection.start(options)})
      end)

    assert_receive {:created_native, ^creator, {:ok, pid}}, 5_000
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
    Process.exit(configured_owner, :kill)

    configured_owner = spawn(fn -> Process.sleep(:infinity) end)
    options = Keyword.put(context.options, :owner, configured_owner)
    File.write!(Path.join(context.store, "mode"), "silent")
    File.rm(Path.join(context.store, "helper.pid"))

    starter =
      spawn(fn ->
        send(parent, {:opening_native, Connection.start(options)})
      end)

    wait_for_file(
      Path.join(context.store, "helper.pid"),
      System.monotonic_time(:millisecond) + 1_000
    )

    Process.exit(configured_owner, :kill)
    assert_receive {:opening_native, {:error, %Error{code: :connection_closed}}}, 1_000
    assert_helper_stopped(context.store, 1_000)
    refute Process.alive?(starter)

    File.write!(Path.join(context.store, "mode"), "silent")
    File.rm(Path.join(context.store, "helper.pid"))
    creator = spawn(fn -> Connection.start(Keyword.put(context.options, :owner, parent)) end)
    creator_monitor = Process.monitor(creator)

    wait_for_file(
      Path.join(context.store, "helper.pid"),
      System.monotonic_time(:millisecond) + 1_000
    )

    Process.exit(creator, :kill)
    assert_receive {:DOWN, ^creator_monitor, :process, ^creator, :killed}
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 rejects direct messages, foreign identities and exhausted close IDs", context do
    parent = self()

    foreign =
      spawn(fn ->
        Process.put(:wotex_coap_owner, :foreign)
        send(parent, {:foreign_ready, self()})
        Process.sleep(:infinity)
      end)

    assert_receive {:foreign_ready, ^foreign}
    assert {:error, %Error{code: :invalid_session}} = Connection.close(foreign)
    Process.exit(foreign, :kill)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :invalid_session}} = GenServer.call(pid, :foreign)
    send(pid, :foreign)
    assert Process.alive?(pid)

    :sys.replace_state(pid, fn state ->
      %{state | command: %{state.command | next_id: :exhausted}}
    end)

    assert {:error, %Error{code: :sequence_exhausted}} = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    :sys.replace_state(pid, fn state -> %{state | command: :invalid} end)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)
  end

  test "WCO-N02 closes on exact Port exit and rejected nonblocking writes", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    %{port: port} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    send(pid, {:EXIT, port, :fault})
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    closed = Port.open({:spawn_executable, ~c"/bin/cat"}, [:binary, :use_stdio])
    Port.close(closed)
    :sys.replace_state(pid, fn state -> %{state | port: closed} end)
    assert {:error, %Error{code: :native_unavailable}} = Connection.close(pid)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 bounds ready and close waits by the caller and local cleanup budgets", context do
    File.write!(Path.join(context.store, "mode"), "silent")
    started = System.monotonic_time(:millisecond)

    assert {:error, %Error{code: :timeout}} =
             Connection.start(Keyword.put(context.options, :timeout, 500))

    assert System.monotonic_time(:millisecond) - started < 1_500
    assert_helper_stopped(context.store, 1_000)

    File.rm(Path.join(context.store, "helper.pid"))

    assert {:error, %Error{code: :timeout}} =
             Connection.start(Keyword.put(context.options, :timeout, 1))

    File.write!(Path.join(context.store, "mode"), "close_silent")
    assert {:ok, pid} = Connection.start(context.options)
    started = System.monotonic_time(:millisecond)
    assert {:error, %Error{code: :timeout}} = Connection.close(pid)
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-C03 WCO-N02 owner death releases the exact helper within 1000 ms", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    parent = self()

    owner =
      spawn(fn ->
        result = Connection.start(context.options)
        send(parent, {:native_started, self(), result})
        Process.sleep(:infinity)
      end)

    assert_receive {:native_started, ^owner, {:ok, connection}}, 5_000
    monitor = Process.monitor(connection)
    started = System.monotonic_time(:millisecond)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^connection, _}, 1_000
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  defp options(executable, manifest, store) do
    [
      host: "127.0.0.1",
      port: 5683,
      timeout: 3_000,
      security: security(store),
      native_backend: %{executable: executable, manifest: manifest}
    ]
  end

  defp security(store) do
    {:ok, security} =
      Security.new(%{
        mode: :oscore,
        master_secret: secret_canary(),
        master_salt: <<>>,
        sender_id: <<>>,
        recipient_id: <<1>>,
        context_store: store
      })

    security
  end

  defp secret_canary, do: <<0::128>>
  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}

  defp assert_helper_stopped(store, timeout) do
    path = Path.join(store, "helper.pid")
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_file(path, deadline)

    os_pid =
      path
      |> File.read!()
      |> String.trim()

    wait_for_exit(os_pid, deadline)
    refute process_alive?(os_pid)
  end

  defp wait_for_file(path, deadline) do
    if not File.exists?(path) and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(5)
      wait_for_file(path, deadline)
    end
  end

  defp wait_for_exit(os_pid, deadline) do
    if process_alive?(os_pid) and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(5)
      wait_for_exit(os_pid, deadline)
    end
  end

  defp process_alive?(os_pid) do
    case System.cmd("/bin/kill", ["-0", os_pid],
           stderr_to_stdout: true,
           env: cleared_environment()
         ) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp cleared_environment,
    do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)

  defp digest(path) do
    :sha256
    |> :crypto.hash(File.read!(path))
    |> Base.encode16(case: :lower)
  end

  defp manifest(hash) do
    Jason.encode!(%{
      "schema" => "wotex.coap.native@1",
      "backend" => %{"name" => "libcoap", "version" => "4.3.5", "revision" => @revision},
      "executables" => %{"wotex-coap-oscore" => %{"sha256" => hash}}
    })
  end

  defp helper_source do
    """
    #!/usr/bin/env elixir
    :logger.remove_handler(:default)
    revision = "#{@revision}"
    ["--custody", directory] = System.argv()
    File.write!(Path.join(directory, "arguments"), Enum.join(System.argv(), "\\n"))
    File.write!(Path.join(directory, "helper.pid"), System.pid())
    mode = directory |> Path.join("mode") |> File.read!() |> String.trim()

    raw = fn bytes ->
      {:ok, output} = :file.open(~c"/dev/fd/1", [:raw, :write, :binary])
      :ok = :file.write(output, bytes)
      :ok = :file.close(output)
    end

    ready_line = ~s({"version":1,"event":"ready","backend":"libcoap","revision":"\#{revision}"}\\n)

    ready = fn ->
      case mode do
        "split" ->
          {left, right} = String.split_at(ready_line, 32)
          raw.(left)
          Process.sleep(50)
          raw.(right)

        "extra_ready" ->
          raw.(ready_line <> ready_line)

        _ ->
          IO.write(ready_line)
      end
    end

    id = fn line ->
      [_, value] = Regex.run(~r/"id":"([^"]+)"/, line)
      value
    end

    response = fn request_id ->
      ~s({"version":1,"id":"\#{request_id}","ok":true,"result":null}\\n)
    end

    reply = fn request_id -> IO.write(response.(request_id)) end

    case mode do
      "silent" ->
        Process.sleep(:infinity)

      "wrong_ready" ->
        IO.write(~s({"version":1,"event":"ready","backend":"other","revision":"\#{revision}"}\\n))
        Process.sleep(:infinity)

      "duplicate_ready_key" ->
        IO.write(~s({"version":1,"version":1,"event":"ready","backend":"libcoap","revision":"\#{revision}"}\\n))
        Process.sleep(:infinity)

      "truncated" ->
        IO.write(~s({"version":1,"padding":") <> String.duplicate("x", 65_536))
        Process.sleep(50)

      "oversize" ->
        IO.write(String.duplicate("x", 131_072) <> "\\n")
        Process.sleep(:infinity)

      _ ->
        ready.()
        open = IO.read(:stdio, :line)
        File.write!(Path.join(directory, "open.json"), open)
        open_id = id.(open)

        case mode do
          "wrong_open_id" ->
            reply.("wrong")
            Process.sleep(:infinity)

          "open_error" ->
            IO.write(~s({"version":1,"id":"\#{open_id}","ok":false,"error":{"code":"context_store_locked"}}\\n))
            Process.sleep(:infinity)

          "duplicate" ->
            reply.(open_id)
            reply.(open_id)
            Process.sleep(:infinity)

          "unsolicited" ->
            reply.(open_id)
            Process.sleep(50)
            IO.write("{}\\n")
            Process.sleep(:infinity)

          "exit_after_open" ->
            reply.(open_id)
            Process.sleep(50)

          _ ->
            reply.(open_id)
            close = IO.read(:stdio, :line)

            if is_binary(close) do
              File.write!(Path.join(directory, "close.json"), close)

              case mode do
                "close_silent" ->
                  Process.sleep(:infinity)

                "close_error" ->
                  IO.write(~s({"version":1,"id":"\#{id.(close)}","ok":false,"error":{"code":"busy"}}\\n))
                  Process.sleep(:infinity)

                "close_malformed" ->
                  IO.write("{}\\n")
                  Process.sleep(:infinity)

                "close_partial_exit" ->
                  raw.(String.duplicate("x", 65_536))
                  Process.sleep(50)

                "close_extra" ->
                  line = response.(id.(close))
                  raw.(line <> line)
                  Process.sleep(:infinity)

                "close_exit" ->
                  :ok

                "split" ->
                  line = response.(id.(close))
                  {left, right} = String.split_at(line, 24)
                  raw.(left)
                  Process.sleep(50)
                  raw.(right)

                _ ->
                  reply.(id.(close))
              end
            end
        end
    end
    """
  end

  defp stubborn_helper_source do
    """
    #!/bin/sh
    trap '' TERM
    directory="$2"
    printf '%s' "$$" > "$directory/helper.pid"
    printf '%s\\n' '{"version":1,"event":"ready","backend":"libcoap","revision":"#{@revision}"}'
    IFS= read -r open
    printf '%s\\n' '{"version":1,"id":"1","ok":true,"result":null}'
    IFS= read -r close
    while :; do :; done
    """
  end
end
