Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.CoreBluetoothHostTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.{NativeCommand, NativeLane}

  @root Path.expand("../../..", __DIR__)
  @identifier "01234567-89ab-cdef-0123-456789abcdef"
  @ready %{
    "version" => 1,
    "event" => "ready",
    "backend" => "corebluetooth-native",
    "revision" => "1"
  }

  setup_all do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-cb-host-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    cc = System.find_executable("cc") || flunk("native host tests require cc")
    cxx = System.find_executable("c++") || flunk("native host tests require C++17")
    command = Path.join(directory, "command")
    guardian = Path.join(directory, "guardian")
    peer = Path.join(directory, "peer")

    assert {:ok, _, 0} =
             NativeCommand.bootstrap(
               cc,
               Path.join(@root, "priv/bluez/native/build_command.c"),
               command
             )

    assert {:ok, output, 0} =
             NativeCommand.run(
               command,
               cc,
               ~w(-std=c11 -O1 -Wall -Wextra -Werror) ++
                 [Path.join(@root, "priv/bluez/native/custody.c"), "-o", guardian],
               cd: directory
             )

    assert output == ""

    assert {:ok, output, 0} =
             NativeCommand.run(
               command,
               cxx,
               NativeLane.flags() ++
                 ~w(-std=c++17 -O1 -Wall -Wextra -Werror -pedantic) ++
                 [Path.join(@root, "test/native/corebluetooth_host_peer.cpp"), "-o", peer],
               cd: directory,
               timeout: NativeLane.timeout(15_000),
               env: NativeLane.environment([])
             )

    assert output == ""
    {:ok, directory: directory, command: command, guardian: guardian, peer: peer}
  end

  test "closed input never opens a driver and malformed input reveals no private fields", context do
    assert {:ok, output, 1} =
             NativeCommand.run(context.command, context.peer, [], cd: context.directory)

    assert Jason.decode!(String.trim(output)) == @ready
    port = start(context)
    assert frame(port) == @ready
    Port.command(port, "{\"private\":\"#{@identifier}\",\"private\":0}\n")
    assert_exit(port, 2)
  end

  test "generation, all discovery records, modes and byte envelopes survive real process IO",
       context do
    port = opened(context)
    send_request(port, "1", "discover", %{})

    assert %{"result" => %{"characteristics" => items}, "generation" => 7, "ok" => true} =
             frame(port)

    assert length(items) == 256
    assert Enum.map(items, & &1["route"]) == Enum.to_list(1..256)
    assert Enum.all?(items, &(&1["service_uuid"] == "0000181a-0000-1000-8000-00805f9b34fb"))
    send_request(port, "2", "read", %{"address" => address()})
    assert success("2", %{"type" => "bytes", "base64" => "AP8="}) == frame(port)

    for {id, operation, result} <- [
          {"3", "write", nil},
          {"4", "write_command",
           %{"write_mode" => "without_response", "evidence" => "native_queue_accepted"}}
        ] do
      send_request(port, id, operation, %{
        "address" => address(),
        "value" => %{"type" => "bytes", "base64" => "AP8="}
      })

      assert frame(port) == %{
               "version" => 1,
               "generation" => 7,
               "event" => "write_submitted",
               "id" => id
             }

      assert frame(port) == success(id, result)
    end

    close(port)
  end

  test "partial input EOF reveals only the passive ready receipt", context do
    assert {:ok, output, 2} =
             NativeCommand.run(context.command, context.peer, ["--partial-eof"],
               cd: context.directory
             )

    assert Jason.decode!(String.trim(output)) == @ready
  end

  test "unconfirmed cleanup cannot produce a successful close receipt", context do
    port = opened(context, "cleanup-failure")
    send_request(port, "1", "write", %{"address" => address(), "value" => value()})
    assert %{"event" => "write_submitted"} = frame(port)
    send_request(port, "close", "close", %{})

    assert %{
             "id" => "1",
             "error" => %{
               "code" => "cleanup_timeout",
               "submitted" => true,
               "cleanup_confirmed" => false
             }
           } = frame(port)

    assert %{
             "id" => "close",
             "ok" => false,
             "error" => %{"code" => "cleanup_timeout", "cleanup_confirmed" => false}
           } = frame(port)

    assert_exit(port, 0)
  end

  test "wrong route, generation and canonical bytes dispatch nothing", context do
    port = opened(context)

    for {id, parameters, expected} <- [
          {"1", %{"address" => %{"generation" => 8, "route" => 1}, "value" => value()},
           "stale_discovery"},
          {"2", %{"address" => %{"generation" => 7, "route" => 257}, "value" => value()},
           "invalid_options"},
          {"3", %{"address" => address(), "value" => %{"type" => "bytes", "base64" => "Af=="}},
           "invalid_value"}
        ] do
      send_request(port, id, "write", parameters)
      assert %{"error" => %{"code" => ^expected, "submitted" => false}, "id" => ^id} = frame(port)
    end

    close(port)
  end

  test "a busy operation is never queued and close overtakes an accepted write", context do
    port = opened(context, "hold")
    send_request(port, "1", "write", %{"address" => address(), "value" => value()})
    assert %{"event" => "write_submitted", "id" => "1"} = frame(port)
    send_request(port, "2", "read", %{"address" => address()})
    assert %{"error" => %{"code" => "busy", "submitted" => false}, "id" => "2"} = frame(port)
    send_request(port, "close", "close", %{})

    assert %{"error" => %{"submitted" => true, "cleanup_confirmed" => true}, "id" => "1"} =
             frame(port)

    assert success("close", nil) == frame(port)
    assert_exit(port, 0)
  end

  test "the original deadline wins over a stalled or late producer", context do
    for mode <- ["hold", "late"] do
      port = opened(context, mode)
      send_request(port, "1", "write_command", %{"address" => address(), "value" => value()}, 30)
      assert %{"event" => "write_submitted"} = frame(port)

      assert %{
               "error" => %{
                 "code" => "timeout",
                 "cause" => "timeout",
                 "submitted" => true,
                 "cleanup_confirmed" => true
               }
             } = frame(port)

      assert %{"event" => "connection_lost"} = frame(port)
      assert_exit(port, 1)
    end
  end

  test "a successful write without a marker cannot produce success", context do
    port = opened(context, "missing-marker")
    send_request(port, "1", "write_command", %{"address" => address(), "value" => value()})
    assert %{"event" => "connection_lost"} = frame(port)
    assert_exit(port, 70)
  end

  test "reused request identities terminate the generation", context do
    port = opened(context)
    send_request(port, "1", "health", %{})
    assert success("1", %{"connected" => true, "services_resolved" => true}) == frame(port)
    send_request(port, "1", "health", %{})
    assert %{"event" => "connection_lost"} = frame(port)
    assert_exit(port, 2)
  end

  test "unread output reaches a finite reply bound and exits", context do
    assert {:ok, "ok blocked-output\n", 0} =
             NativeCommand.run(context.command, context.peer, ["--blocked-output"],
               cd: context.directory,
               timeout: NativeLane.timeout(5000),
               env: NativeLane.environment([])
             )
  end

  defp start(context, mode \\ "normal") do
    port =
      Port.open({:spawn_executable, context.guardian}, [
        :binary,
        :exit_status,
        {:line, 131_071},
        args: ["500", "131072", "65536", context.directory, context.peer, mode],
        env:
          Enum.map(
            NativeLane.environment(Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)),
            fn {name, value} ->
              {String.to_charlist(name),
               if(is_nil(value), do: false, else: String.to_charlist(value))}
            end
          )
      ])

    on_exit(fn ->
      try do
        Port.close(port)
      rescue
        ArgumentError -> :ok
      end
    end)

    port
  end

  defp opened(context, mode \\ "normal") do
    port = start(context, mode)
    assert frame(port) == @ready

    send_request(port, "open", "open", %{
      "identifier" => @identifier,
      "generation" => 7,
      "permission" => "require_authorized",
      "pairing" => "system"
    })

    assert frame(port) == success("open", %{"generation" => 7})
    port
  end

  defp send_request(port, id, operation, parameters, timeout \\ 1000) do
    assert Port.command(
             port,
             Jason.encode!(%{
               version: 1,
               id: id,
               operation: operation,
               parameters: parameters,
               timeout_ms: timeout
             }) <> "\n"
           )
  end

  defp frame(port) do
    assert_receive {^port, {:data, {:eol, line}}}, NativeLane.timeout(5000)
    Jason.decode!(line)
  end

  defp assert_exit(port, status) do
    assert_receive {^port, {:exit_status, ^status}}, NativeLane.timeout(5000)
    refute_receive {^port, {:data, _}}
  end

  defp close(port) do
    send_request(port, "close", "close", %{})
    assert success("close", nil) == frame(port)
    assert_exit(port, 0)
  end

  defp address, do: %{"generation" => 7, "route" => 1}
  defp value, do: %{"type" => "bytes", "base64" => "AP8="}

  defp success(id, result),
    do: %{"version" => 1, "generation" => 7, "id" => id, "ok" => true, "result" => result}
end
