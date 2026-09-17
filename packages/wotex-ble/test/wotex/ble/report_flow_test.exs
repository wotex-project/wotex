defmodule Wotex.BLE.ReportFlowTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.BLE.BlueZ.{ReportFlow, Stream, SubscriptionOwner}

  @generation "0123456789abcdef0123456789abcdef"
  # Receive waits share the owner establishment deadline instead of scheduler timing.
  @owner_deadline 1000

  test "WBL-B02 owner consumption acknowledges only the contiguous report prefix" do
    binding = stream_binding()
    first_owner = spawn_owner()
    second_owner = spawn_owner()

    flow = ReportFlow.new(@generation)
    assert {:ok, flow} = ReportFlow.open(flow, "1", first_owner, 2)
    assert {:ok, flow} = ReportFlow.open(flow, "2", second_owner, 2)

    assert {:ok, {:ok, <<1>>, _}, first_token, flow} =
             ReportFlow.report(flow, report("1", 1, 1), binding, 101, first_owner)

    second_binding = %{binding | subscription_id: "2"}

    assert {:ok, {:ok, <<2>>, _}, second_token, flow} =
             ReportFlow.report(flow, report("2", 2, 2), second_binding, 103, second_owner)

    assert {:ok, nil, flow} = ReportFlow.consume(flow, second_owner, 2, second_token)

    assert {:ok,
            %{
              "event" => "report_ack",
              "session_generation" => @generation,
              "report_sequence" => 2,
              "acknowledged_bytes" => 204
            }, flow} = ReportFlow.consume(flow, first_owner, 1, first_token)

    assert flow.records == %{}
    assert flow.outstanding_bytes == 0
    assert {:ok, nil, ^flow} = ReportFlow.consume(flow, first_owner, 1, first_token)
  end

  test "WBL-B02 retirement consumes only that stream and leaves no tombstone" do
    binding = stream_binding()
    first_owner = spawn_owner()
    second_owner = spawn_owner()
    flow = ReportFlow.new(@generation)
    assert {:ok, flow} = ReportFlow.open(flow, "1", first_owner, 2)
    assert {:ok, flow} = ReportFlow.open(flow, "2", second_owner, 2)

    assert {:ok, _, _, flow} =
             ReportFlow.report(flow, report("1", 1, 1), binding, 100, first_owner)

    second_binding = %{binding | subscription_id: "2"}

    assert {:ok, _, second_token, flow} =
             ReportFlow.report(flow, report("2", 2, 2), second_binding, 200, second_owner)

    assert {:ok, _, _, flow} =
             ReportFlow.report(flow, report("1", 3, 3), binding, 300, first_owner)

    assert {:ok, "1", ^first_owner, %{"report_sequence" => 1, "acknowledged_bytes" => 100}, flow} =
             ReportFlow.retire(flow, retirement("1", 3))

    refute ReportFlow.active?(flow, "1")
    assert ReportFlow.active?(flow, "2")
    assert :invalid = ReportFlow.retire(flow, retirement("1", 3))
    assert :invalid = ReportFlow.report(flow, report("1", 4, 4), binding, 100, first_owner)

    assert {:ok, %{"report_sequence" => 3, "acknowledged_bytes" => 600}, flow} =
             ReportFlow.consume(flow, second_owner, 2, second_token)

    assert flow.records == %{}
    assert flow.outstanding_bytes == 0
  end

  test "WBL-B02 report identity, windows and byte bounds fail closed" do
    owner = spawn_owner()
    binding = stream_binding()
    flow = ReportFlow.new(@generation)
    assert {:ok, flow} = ReportFlow.open(flow, "1", owner, 1)

    assert :invalid = ReportFlow.open(flow, "01", owner, 1)
    assert :invalid = ReportFlow.open(flow, "2", owner, 0)
    assert :invalid = ReportFlow.report(flow, report("1", 2, 1), binding, 100, owner)

    wrong_generation =
      report("1", 1, 1)
      |> Map.put("session_generation", String.duplicate("a", 32))

    assert :invalid = ReportFlow.report(flow, wrong_generation, binding, 100, owner)
    assert {:ok, _, token, flow} = ReportFlow.report(flow, report("1", 1, 1), binding, 100, owner)
    assert :invalid = ReportFlow.report(flow, report("1", 2, 2), binding, 100, owner)
    assert {:ok, nil, ^flow} = ReportFlow.consume(flow, self(), 1, token)
    assert {:ok, %{"report_sequence" => 1}, _} = ReportFlow.consume(flow, owner, 1, token)
  end

  test "WBL-B02 terminal controls and malformed internal calls cannot mint credit" do
    owner = spawn_owner()
    binding = stream_binding()
    flow = ReportFlow.new(@generation)
    assert {:ok, flow} = ReportFlow.open(flow, "1", owner, 1)

    terminal =
      report("1", 1, 1)
      |> Map.drop(["report_sequence"])
      |> Map.merge(%{
        "event" => "error",
        "value" => nil,
        "metadata" => %{"error" => %{"code" => "subscription_lost"}}
      })

    assert {:ok, {:error, %Wotex.BLE.Error{code: :subscription_lost}}} =
             ReportFlow.terminal(flow, terminal, binding, owner)

    assert :invalid = ReportFlow.terminal(flow, Map.put(terminal, "extra", true), binding, owner)
    assert :invalid = ReportFlow.terminal(:invalid, terminal, binding, owner)
    assert :invalid = ReportFlow.report(:invalid, %{}, binding, 1, owner)
    assert {:ok, nil, ^flow} = ReportFlow.consume(flow, :not_a_pid, 1, :not_a_reference)
    assert :invalid = ReportFlow.consume(:invalid, owner, 1, make_ref())
    assert :invalid = ReportFlow.retire(:invalid, retirement("1", 0))
    assert :invalid = ReportFlow.open(flow, :not_an_identifier, owner, 1)

    record = %{bytes: 1, consumed: false, owner: owner, stream: "1", token: make_ref()}

    exhausted = %ReportFlow{
      generation: @generation,
      acknowledged_bytes: 0xFFFF_FFFF_FFFF_FFFF,
      outstanding_bytes: 1,
      records: %{1 => record},
      streams: %{"1" => %{owner: owner, last_sequence: 1, outstanding: 1, window: 1}}
    }

    assert :invalid = ReportFlow.consume(exhausted, owner, 1, record.token)
  end

  test "WBL-B02 stream owner acknowledges only admitted receiver delivery" do
    connection = %{pid: self(), reference: make_ref()}
    tag = make_ref()
    token = make_ref()
    config = config(self(), 2)

    assert {:ok, owner} =
             SubscriptionOwner.start(
               connection,
               config,
               {self(), tag},
               token,
               now() + @owner_deadline
             )

    send(owner, {token, {:ok, stream_binding()}})
    assert_receive {^tag, {:ok, handle}}, @owner_deadline
    delivery = make_ref()
    metadata = %{source: :bluez_value_change}
    send(owner, {:ble_stream, "1", {1, delivery}, {:ok, <<1>>, metadata}})

    assert_receive {:wotex_ble, reference, {:ok, <<1>>, ^metadata}}, @owner_deadline
    assert reference == handle.reference

    assert_receive {:ble_report_consumed, connection_reference, ^owner, 1, ^delivery},
                   @owner_deadline

    assert connection_reference == connection.reference
    GenServer.stop(owner)

    receiver = spawn_owner()
    send(receiver, :already_full)
    tag = make_ref()
    token = make_ref()
    config = config(receiver, 1)

    assert {:ok, owner} =
             SubscriptionOwner.start(
               connection,
               config,
               {self(), tag},
               token,
               now() + @owner_deadline
             )

    send(owner, {token, {:ok, stream_binding()}})
    assert_receive {^tag, {:ok, _}}, @owner_deadline
    rejected = make_ref()
    send(owner, {:ble_stream, "1", {1, rejected}, {:ok, <<1>>, metadata}})
    assert_receive {:"$gen_cast", {_, :unsubscribe, ^owner, _}}, @owner_deadline
    refute_receive {:ble_report_consumed, _, ^owner, 1, ^rejected}, 20
    GenServer.stop(owner)
  end

  defp stream_binding do
    {:ok, binding} = Stream.establishment(establishment("1"))
    binding
  end

  defp config(receiver, queue_limit) do
    {:ok, config} =
      Stream.options(
        %{
          address: %{
            service: "0000180f-0000-1000-8000-00805f9b34fb",
            characteristic: "00002a19-0000-1000-8000-00805f9b34fb",
            object_path: "/characteristic",
            handle: 1,
            generation: 1
          },
          receiver: receiver,
          max_queue_length: queue_limit
        },
        1000,
        self()
      )

    config
  end

  defp establishment(id) do
    %{
      "subscription_id" => id,
      "generation" => 1,
      "characteristic" => %{
        "service_uuid" => "0000180f-0000-1000-8000-00805f9b34fb",
        "characteristic_uuid" => "00002a19-0000-1000-8000-00805f9b34fb",
        "service_path" => "/service",
        "object_path" => "/characteristic",
        "handle" => 1,
        "generation" => 1,
        "flags" => ["notify"]
      },
      "requested_mode" => "auto",
      "effective_mode" => "notify"
    }
  end

  defp report(id, sequence, byte) do
    binding = establishment(id)

    %{
      "version" => 1,
      "session_generation" => @generation,
      "report_sequence" => sequence,
      "subscription_id" => id,
      "generation" => 1,
      "event" => "value",
      "value" => %{"type" => "bytes", "base64" => Base.encode64(<<byte>>)},
      "metadata" =>
        binding
        |> Map.take(["characteristic", "requested_mode", "effective_mode"])
        |> Map.put("source", "bluez_value_change")
    }
  end

  defp retirement(id, sequence) do
    %{
      "version" => 1,
      "event" => "stream_retired",
      "session_generation" => @generation,
      "subscription_id" => id,
      "generation" => 1,
      "last_report_sequence" => sequence
    }
  end

  defp spawn_owner do
    pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    pid
  end

  defp now, do: System.monotonic_time(:millisecond)
end
