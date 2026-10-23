defmodule Wotex.BLE.CoreBluetoothStreamTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BLE.CoreBluetooth.{Characteristic, ReportFlow, Stream}

  @vectors Path.expand("../../../priv/fixtures/corebluetooth-notifications-v1.json", __DIR__)
  @external_resource @vectors
  @cells Jason.decode!(File.read!(@vectors))["mode_cases"]
  @modes %{"auto" => :auto, "notify" => :notify, "indicate" => :indicate}

  test "public mode admission consumes all independent literal SDK mode cells" do
    for cell <- @cells do
      characteristic = %{
        binding("1", 1).characteristic
        | notify: cell["notify"],
          indicate: cell["indicate"]
      }

      case Stream.mode(characteristic, @modes[cell["requested"]]) do
        {:ok, mode} -> assert Atom.to_string(mode) == cell["effective"]
        {:error, %{code: :not_supported}} -> assert cell["effective"] == nil
      end
    end

    for change <- [
          receiver: :none,
          mode: :guess,
          max_queue_length: 0,
          max_queue_length: 10_001,
          timeout: 0,
          unknown: true
        ] do
      request = Map.merge(%{address: %{service: "181a", characteristic: "2a19"}}, Map.new([change]))
      assert {:error, _} = Stream.options(request, 1000, self())
    end
  end

  test "credit is per stream and advances only through a consumed contiguous prefix" do
    other = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Process.exit(other, :kill) end)
    assert {:ok, flow} = ReportFlow.open(ReportFlow.new(7), self(), binding("1", 1))
    assert {:ok, flow} = ReportFlow.open(flow, other, binding("2", 2))

    assert {:ok, _, "1", {1, first}, {:ok, <<0, 255>>, metadata}, flow} =
             ReportFlow.report(flow, report("1", 1, 1))

    assert metadata.source == :corebluetooth_value_update
    assert metadata.characteristic.route == 1
    assert {:ok, _, "1", {2, second}, _, flow} = ReportFlow.report(flow, report("1", 1, 2))
    assert {:ok, ^other, "2", {1, third}, _, flow} = ReportFlow.report(flow, report("2", 2, 1))
    assert {nil, ^flow} = ReportFlow.consume(flow, other, "1", 1, first)
    assert {nil, ^flow} = ReportFlow.consume(flow, self(), "1", 1, make_ref())
    assert {nil, flow} = ReportFlow.consume(flow, self(), "1", 2, second)

    assert {%{"subscription_id" => "2", "sequence" => 1}, flow} =
             ReportFlow.consume(flow, other, "2", 1, third)

    assert {%{"subscription_id" => "1", "sequence" => 2, "generation" => 7} = ack, flow} =
             ReportFlow.consume(flow, self(), "1", 1, first)

    assert map_size(ack) == 6
    assert {nil, ^flow} = ReportFlow.consume(flow, self(), "1", 1, first)
    assert flow.streams["1"].records == %{}
  end

  test "malformed reports and false retirement cannot release records or reopen a used route" do
    assert {:ok, flow} = ReportFlow.open(ReportFlow.new(7), self(), binding("1", 1))
    frame = report("1", 1, 1)

    for changed <- [
          Map.put(frame, "extra", true),
          %{frame | "generation" => 8},
          %{frame | "generation" => 7.0},
          %{frame | "subscription_id" => "01"},
          %{frame | "route" => 2},
          %{frame | "sequence" => 2},
          %{frame | "sequence" => 1.0},
          %{frame | "value" => %{"type" => "bytes", "base64" => "!"}}
        ] do
      assert :invalid = ReportFlow.report(flow, changed)
    end

    assert {:ok, _, _, _, _, flow} = ReportFlow.report(flow, frame)
    assert {:ok, _, _, _, _, flow} = ReportFlow.report(flow, report("1", 1, 2))
    assert :invalid = ReportFlow.report(flow, report("1", 1, 3))

    fence = %{
      "version" => 1,
      "generation" => 7,
      "stream_version" => 1,
      "event" => "notification_retired",
      "subscription_id" => "1",
      "route" => 1,
      "last_sequence" => 2
    }

    assert :invalid = ReportFlow.retire(flow, %{fence | "last_sequence" => 3})
    assert {:ok, "1", _, %{"sequence" => 2}, flow} = ReportFlow.retire(flow, fence)
    assert ReportFlow.used?(flow, 1)
    assert flow.streams == %{}
    assert :invalid = ReportFlow.open(flow, self(), binding("2", 1))
    assert :invalid = ReportFlow.report(flow, frame)
  end

  test "sixteen live streams and sixty-four shared credits are independent limits" do
    flow =
      Enum.reduce(1..16, ReportFlow.new(7), fn number, flow ->
        assert {:ok, flow} =
                 ReportFlow.open(flow, self(), %{
                   binding(Integer.to_string(number), number)
                   | credit: 4
                 })

        flow
      end)

    assert map_size(flow.streams) == 16
    assert :invalid = ReportFlow.open(flow, self(), binding("17", 17))

    flow =
      Enum.reduce(1..4, ReportFlow.new(7), fn number, flow ->
        assert {:ok, flow} =
                 ReportFlow.open(flow, self(), %{
                   binding(Integer.to_string(number), number)
                   | credit: 16
                 })

        flow
      end)

    assert :invalid = ReportFlow.open(flow, self(), binding("5", 5))
  end

  test "Runtime metadata keeps backend, mode and native route identity separate" do
    assert {:ok, flow} = ReportFlow.open(ReportFlow.new(7), self(), binding("1", 1))
    assert {:ok, _, _, _, {:ok, bytes, metadata}, _} = ReportFlow.report(flow, report("1", 1, 1))

    assert {:ok, form} =
             Wotex.Form.new(%{"href" => "ble://route/181a/2a19", "op" => "observeproperty"},
               for: :property
             )

    assert {:ok, mapping} = Wotex.BLE.Mapping.command(form, :observeproperty, nil)

    mapping = Map.put(mapping, :backend, Wotex.BLE.CoreBluetooth)
    assert {:ok, ^bytes, ^metadata} = Wotex.BLE.RuntimeFrame.validate(bytes, metadata, mapping)

    assert {:error, _} =
             Wotex.BLE.RuntimeFrame.validate(bytes, metadata, %{mapping | backend: Wotex.BLE.BlueZ})

    assert {:error, _} =
             Wotex.BLE.RuntimeFrame.validate(
               bytes,
               %{metadata | effective_mode: :indicate},
               mapping
             )

    assert {:error, _} =
             Wotex.BLE.RuntimeFrame.validate(bytes, Map.put(metadata, :extra, true), mapping)

    assert :ignore =
             Wotex.BLE.RuntimeFrame.validate(bytes, metadata, %{
               mapping
               | address: %{mapping.address | native_route: {:core_bluetooth, 2}}
             })
  end

  test "malformed selectors and transport envelopes are rejected before stream admission" do
    alias Wotex.BLE.CoreBluetooth.{Options, Response}

    assert {:error, _} = Options.new(nil, self())
    assert {:error, _} = Stream.options(nil, 100, self())
    assert {:error, _} = Stream.mode(nil, :auto)
    refute Stream.handle?(nil)
    assert :invalid = Stream.identifier(nil)
    assert :invalid = ReportFlow.retire(ReportFlow.new(7), %{})

    lost = %{"version" => 1, "generation" => 7, "event" => "connection_lost", "code" => "busy"}
    assert {:lost, :busy} = Response.decode(lost, 7)
    assert :invalid = Response.decode(%{lost | "code" => "ok"}, 7)
    assert :invalid = Response.decode(%{lost | "code" => "unknown"}, 7)
    assert :invalid = Response.decode(%{"version" => 1, "generation" => 7}, 7)

    assert :invalid =
             Response.decode(
               %{"version" => 1, "generation" => 7, "id" => "2", "ok" => false, "error" => nil},
               7
             )
  end

  defp binding(id, route) do
    {:ok, characteristic} =
      Characteristic.new(%{
        service: "181a",
        characteristic: "2a19",
        generation: 7,
        route: route,
        read: true,
        write: true,
        write_without_response: true,
        notify: true,
        indicate: false
      })

    %{
      subscription_id: id,
      characteristic: characteristic,
      credit: 2,
      requested_mode: :auto,
      effective_mode: :notify
    }
  end

  defp report(id, route, sequence),
    do: %{
      "version" => 1,
      "generation" => 7,
      "stream_version" => 1,
      "event" => "notification",
      "subscription_id" => id,
      "route" => route,
      "sequence" => sequence,
      "value" => %{"type" => "bytes", "base64" => "AP8="}
    }
end
