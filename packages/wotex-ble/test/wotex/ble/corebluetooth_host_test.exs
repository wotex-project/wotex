Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.CoreBluetoothHostTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.{NativeCommand, NativeLane}

  @root Path.expand("../../..", __DIR__)
  @vectors Path.join(@root, "priv/fixtures/corebluetooth-notification-wire-v1.json")
  @external_resource @vectors
  @wire Jason.decode!(File.read!(@vectors))
  @mode_vectors Path.join(@root, "priv/fixtures/corebluetooth-notifications-v1.json")
  @external_resource @mode_vectors
  @mode_cases Map.fetch!(Jason.decode!(File.read!(@mode_vectors)), "mode_cases")
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

  test "literal stream frames preserve exact establishment, equal values and stop fencing",
       context do
    port = opened(context, "notifications")
    assert @wire["format"] == "wotex.ble.corebluetooth.notification-wire"
    send_frame(port, @wire["subscribe"])
    assert frame(port) == @wire["established"]
    assert frame(port) == @wire["first_report"]
    assert frame(port) == Map.put(@wire["first_report"], "sequence", 2)
    refute_receive {^port, {:data, _}}, 20
    send_frame(port, @wire["unsubscribe"])
    assert frame(port) == @wire["retired"]
    assert frame(port) == success("2", nil)
    send_frame(port, Map.put(@wire["ack"], "sequence", 2))
    send_request(port, "3", "read", %{"address" => address()})

    assert %{"id" => "3", "error" => %{"code" => "not_supported", "submitted" => false}} =
             frame(port)

    send_request(port, "4", "subscribe", subscription(1, 1))
    assert %{"id" => "4", "error" => %{"code" => "not_permitted"}} = frame(port)
    close(port)
  end

  test "mode selection is explicit and refused starts consume no route", context do
    for cell <- @mode_cases do
      route =
        %{{false, false} => 4, {true, false} => 1, {false, true} => 2, {true, true} => 3}[
          {cell["notify"], cell["indicate"]}
        ]

      port = opened(context, "notification-modes")

      send_request(
        port,
        "1",
        "subscribe",
        Map.put(subscription(route, 1), "mode", cell["requested"])
      )

      if effective = cell["effective"] do
        assert %{"ok" => true, "result" => %{"effective_mode" => ^effective, "route" => ^route}} =
                 frame(port)

        assert %{"event" => "notification", "route" => ^route, "sequence" => 1} = frame(port)
      else
        assert %{"error" => %{"code" => "not_supported", "submitted" => false}} = frame(port)
      end

      close(port)
    end

    port = opened(context, "notifications")
    send_request(port, "1", "subscribe", Map.put(subscription(3, 1), "mode", "indicate"))
    assert %{"id" => "1", "error" => %{"code" => "not_supported"}} = frame(port)
    send_request(port, "2", "subscribe", Map.put(subscription(3, 1), "mode", "notify"))

    assert %{
             "id" => "2",
             "result" => %{"requested_mode" => "notify", "effective_mode" => "notify", "route" => 3}
           } = frame(port)

    assert %{"event" => "notification", "subscription_id" => "2", "route" => 3, "sequence" => 1} =
             frame(port)

    send_request(port, "3", "subscribe", subscription(2, 1))
    assert %{"id" => "3", "result" => %{"effective_mode" => "indicate", "route" => 2}} = frame(port)
    assert %{"event" => "notification", "subscription_id" => "3", "route" => 2} = frame(port)
    close(port)
  end

  test "malformed stream parameters refuse without consuming the selected route", context do
    port = opened(context, "notifications")

    invalid = [
      Map.put(subscription(1, 2), "credit", 0),
      Map.put(subscription(1, 2), "credit", 65),
      Map.put(subscription(1, 2), "mode", "guess"),
      Map.put(subscription(1, 2), "stream_version", 2),
      Map.put(subscription(1, 2), "extra", true),
      put_in(subscription(1, 2), ["address", "generation"], 8),
      put_in(subscription(1, 2), ["address", "route"], 257)
    ]

    for {parameters, id} <- Enum.with_index(invalid, 1) do
      send_request(port, Integer.to_string(id), "subscribe", parameters)
      assert %{"error" => %{"code" => "invalid_options", "submitted" => false}} = frame(port)
    end

    send_request(port, "8", "subscribe", subscription(1, 1))
    assert %{"id" => "8", "result" => %{"route" => 1, "credit" => 1}} = frame(port)
    assert %{"event" => "notification", "subscription_id" => "8"} = frame(port)
    close(port)
  end

  test "only actual cumulative acknowledgement returns credit and duplicate acknowledgement is inert",
       context do
    port = opened(context, "notifications")
    send_frame(port, @wire["subscribe"])
    assert frame(port) == @wire["established"]
    assert frame(port) == @wire["first_report"]
    assert frame(port) == Map.put(@wire["first_report"], "sequence", 2)
    send_frame(port, @wire["ack"])
    assert frame(port) == Map.put(@wire["first_report"], "sequence", 3)
    send_frame(port, @wire["ack"])
    refute_receive {^port, {:data, _}}, 20
    send_frame(port, Map.put(@wire["ack"], "sequence", 3))
    assert frame(port) == Map.put(@wire["first_report"], "sequence", 4)
    assert frame(port) == Map.put(@wire["first_report"], "sequence", 5)
    close(port)
  end

  test "the literal malformed acknowledgement corpus never grants credit", context do
    assert length(@wire["invalid_acks"]) == 10

    for cell <- @wire["invalid_acks"] do
      port = opened(context, "notifications")
      send_frame(port, @wire["subscribe"])
      assert frame(port) == @wire["established"]
      assert frame(port) == @wire["first_report"]
      assert frame(port) == Map.put(@wire["first_report"], "sequence", 2)

      if sequence = cell["after_ack"] do
        send_frame(port, Map.put(@wire["ack"], "sequence", sequence))
        assert frame(port) == Map.put(@wire["first_report"], "sequence", 3)
      end

      if raw = cell["raw"],
        do: Port.command(port, raw),
        else: send_frame(port, Map.merge(@wire["ack"], cell["changes"]))

      assert %{"event" => "connection_lost"} = frame(port)
      assert_exit(port, 2)
    end
  end

  test "stopped reports retain the shared 64-credit reservation until acknowledged", context do
    port = opened(context, "notifications")
    send_request(port, "1", "subscribe", subscription(1, 64))
    assert %{"id" => "1", "result" => %{"credit" => 64}} = frame(port)

    for sequence <- 1..64,
        do: assert(frame(port) == Map.put(@wire["first_report"], "sequence", sequence))

    send_frame(port, @wire["unsubscribe"])
    assert frame(port) == Map.put(@wire["retired"], "last_sequence", 64)
    assert frame(port) == success("2", nil)
    send_request(port, "3", "subscribe", subscription(2, 1))
    assert %{"id" => "3", "error" => %{"code" => "resource_limit"}} = frame(port)
    send_frame(port, Map.put(@wire["ack"], "sequence", 64))
    send_request(port, "4", "subscribe", subscription(2, 1))
    assert %{"id" => "4", "result" => %{"route" => 2, "credit" => 1}} = frame(port)
    assert %{"event" => "notification", "subscription_id" => "4", "sequence" => 1} = frame(port)
    close(port)
  end

  test "sixteen streams are distinct and the seventeenth is refused before native establishment",
       context do
    port = opened(context, "notifications")

    for id <- 1..16 do
      send_request(port, Integer.to_string(id), "subscribe", subscription(id, 1))
      assert %{"ok" => true, "result" => %{"route" => ^id}} = frame(port)
      assert %{"event" => "notification", "route" => ^id, "sequence" => 1} = frame(port)
    end

    send_request(port, "17", "subscribe", subscription(17, 1))
    assert %{"id" => "17", "error" => %{"code" => "resource_limit"}} = frame(port)
    close(port)
  end

  test "control timeout, active close and unconfirmed cleanup never return establishment success",
       context do
    for mode <- ["notification-hold", "notification-cleanup"] do
      port = opened(context, mode)
      send_request(port, "1", "subscribe", subscription(1, 2), 30)

      if mode == "notification-hold" do
        assert %{"id" => "1", "error" => %{"code" => "timeout", "cleanup_confirmed" => true}} =
                 frame(port)

        assert %{"event" => "connection_lost"} = frame(port)
        assert_exit(port, 1)
      else
        send_request(port, "close", "close", %{})

        assert %{
                 "id" => "1",
                 "error" => %{"code" => "cleanup_timeout", "cleanup_confirmed" => false}
               } = frame(port)

        assert %{"id" => "close", "error" => %{"code" => "cleanup_timeout"}} = frame(port)
        assert_exit(port, 0)
      end
    end
  end

  test "early, substituted and gapped Driver events cannot publish a report", context do
    for mode <- [
          "notification-early",
          "notification-wrong-state",
          "notification-gap",
          "notification-over-credit",
          "notification-foreign",
          "notification-oversize"
        ] do
      port = opened(context, mode)
      send_frame(port, @wire["subscribe"])
      first = frame(port)

      if mode in ["notification-gap", "notification-over-credit", "notification-foreign"] do
        assert first == @wire["established"]

        if mode == "notification-over-credit" do
          assert frame(port) == @wire["first_report"]
          assert frame(port) == Map.put(@wire["first_report"], "sequence", 2)
        end
      else
        assert %{"ok" => false} = first
      end

      assert %{"event" => "connection_lost"} = frame(port)
      assert_exit(port, 70)
    end
  end

  test "notification credits remain available during an active point operation and close overtakes both",
       context do
    port = opened(context, "notification-point-hold")
    send_frame(port, @wire["subscribe"])
    assert frame(port) == @wire["established"]
    frame(port)
    frame(port)
    send_request(port, "2", "write", %{"address" => address(), "value" => value()})
    assert %{"event" => "write_submitted", "id" => "2"} = frame(port)
    send_request(port, "3", "unsubscribe", %{"stream_version" => 1, "subscription_id" => "1"})
    assert %{"id" => "3", "error" => %{"code" => "busy"}} = frame(port)
    send_frame(port, @wire["ack"])
    assert %{"event" => "notification", "sequence" => 3} = frame(port)
    send_request(port, "close", "close", %{})

    assert %{"id" => "2", "error" => %{"submitted" => true, "cleanup_confirmed" => true}} =
             frame(port)

    assert frame(port) == success("close", nil)
    assert_exit(port, 0)
  end

  test "serialized concurrent callbacks preserve 128 maximum-sized reports alongside control IO",
       context do
    port = opened(context, "notification-async")
    send_request(port, "1", "subscribe", subscription(1, 64))
    assert %{"id" => "1", "ok" => true} = frame(port)
    expected = %{"type" => "bytes", "base64" => Base.encode64(:binary.copy(<<255>>, 512))}

    for sequence <- 1..64 do
      assert %{"event" => "notification", "sequence" => ^sequence, "value" => ^expected} =
               frame(port)
    end

    send_frame(port, Map.put(@wire["ack"], "sequence", 64))
    send_request(port, "2", "health", %{})
    frames = for _ <- 1..65, do: frame(port)

    assert Enum.count(
             frames,
             &(&1 == success("2", %{"connected" => true, "services_resolved" => true}))
           ) == 1

    reports = Enum.filter(frames, &(&1["event"] == "notification"))
    assert Enum.map(reports, & &1["sequence"]) == Enum.to_list(65..128)
    assert Enum.all?(reports, &(&1["value"] == expected))
    close(port)
  end

  test "a native write success observed during close remains an uncertain cancelled operation",
       context do
    port = opened(context, "notification-close-success")
    send_request(port, "1", "write", %{"address" => address(), "value" => value()})
    assert %{"event" => "write_submitted", "id" => "1"} = frame(port)
    send_request(port, "close", "close", %{})

    assert %{
             "id" => "1",
             "ok" => false,
             "error" => %{
               "code" => "disconnected",
               "submitted" => true,
               "cleanup_confirmed" => true
             }
           } = frame(port)

    assert frame(port) == success("close", nil)
    assert_exit(port, 0)
  end

  test "empty native updates remain separate sequenced frames", context do
    port = opened(context, "notification-empty")
    send_frame(port, @wire["subscribe"])
    assert frame(port) == @wire["established"]

    for sequence <- 1..2 do
      assert %{
               "event" => "notification",
               "sequence" => ^sequence,
               "value" => %{"type" => "bytes", "base64" => ""}
             } = frame(port)
    end

    close(port)
  end

  test "a full stdout pipe cannot block notification cleanup or admit credit for unsent records",
       context do
    for mode <- ["blocked-notifications", "unsent-notification-ack"] do
      assert {:ok, output, 0} =
               NativeCommand.run(context.command, context.peer, ["--" <> mode],
                 cd: context.directory,
                 timeout: NativeLane.timeout(5000),
                 env: NativeLane.environment([])
               )

      assert output == "ok " <> mode <> "\n"
    end
  end

  test "an unrepresentable cleanup clock fails closed without signed overflow", context do
    assert {:ok, output, 70} =
             NativeCommand.run(context.command, context.peer, ["--clock-overflow"],
               cd: context.directory,
               env: NativeLane.environment([])
             )

    frames = Enum.map(String.split(output, "\n", trim: true), &Jason.decode!/1)

    assert [@ready, %{"event" => "connection_lost", "code" => "clock_regressed", "generation" => 0}] =
             frames
  end

  defp subscription(route, credit),
    do: %{
      "stream_version" => 1,
      "address" => %{"generation" => 7, "route" => route},
      "mode" => "auto",
      "credit" => credit
    }

  defp send_frame(port, frame), do: assert(Port.command(port, Jason.encode!(frame) <> "\n"))

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
