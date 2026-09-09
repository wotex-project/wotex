defmodule Wotex.BLE.BlueZRuntimeInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BLE
  alias Wotex.BLE.{SoftwarePeer, Transport}
  alias Wotex.Runtime.{ConsumedThing, Context, Subscription}
  @moduletag :interop

  setup do
    config = SoftwarePeer.command("reset")
    on_exit(fn -> SoftwarePeer.wait_until(&SoftwarePeer.released?/0, 1500) end)
    %{options: SoftwarePeer.options(config)}
  end

  test "WBL-I02 I03 I04 real ConsumedThing read/write retains typed values and unknown-effect failure",
       %{
         options: options
       } do
    consumed =
      consumer(options, :property, :value, "uint16", %{}, ["readproperty", "writeproperty"])

    context = Context.new!(request_id: "gatt-software-read")

    assert {:ok,
            %{
              status: :ok,
              payload: 4660,
              request_id: "gatt-software-read",
              operation: :readproperty
            }} = ConsumedThing.read_property(consumed, "reading", context)

    assert {:ok, %{status: :ok, payload: :written, operation: :writeproperty}} =
             ConsumedThing.write_property(consumed, "reading", 22_136, context)

    assert {:ok, %{payload: 22_136}} = ConsumedThing.read_property(consumed, "reading", context)

    SoftwarePeer.command("deny", %{label: "value", denied: true})
    consumed = consumer(options, :property, :value, "uint16", %{}, ["writeproperty"])
    context = Context.new!(request_id: "gatt-software-denial")

    assert {:error, %{class: :permanent, details: %{cause: %{code: :not_permitted}}}} =
             ConsumedThing.write_property(consumed, "reading", 42, context)

    assert SoftwarePeer.command("stats")["values"]["value"] == "7856"
    SoftwarePeer.wait_until(&SoftwarePeer.released?/0)
  end

  test "WBL-I01 I03 unsupported media and expired context acquire no native sender", %{
    options: options
  } do
    before = SoftwarePeer.command("stats")

    for media <- ["application/json", "application/octet-stream"] do
      consumed =
        consumer(options, :property, :value, "uint16", %{"contentType" => media}, ["readproperty"])

      context = Context.new!(request_id: "unsupported-media")

      assert {:error, %{details: %{cause: %{code: :unsupported_content_type}}}} =
               ConsumedThing.read_property(consumed, "reading", context)
    end

    consumed = consumer(options, :property, :value, "uint16", %{}, ["readproperty"])
    expired = Context.new!(request_id: "expired", deadline: System.monotonic_time(:millisecond) - 1)
    assert {:error, _} = ConsumedThing.read_property(consumed, "reading", expired)
    after_attempt = SoftwarePeer.command("stats")
    assert after_attempt["calls"] == before["calls"]
    assert after_attempt["native_senders"] == []
  end

  test "WBL-I02 I05 Property and Event values traverse real GATT and their public Runtime owner", %{
    options: options
  } do
    for {kind, mode} <- [
          {:property, :notify},
          {:property, :indicate},
          {:event, :notify},
          {:event, :indicate}
        ] do
      consumed = consumer(options, kind, mode, "uint8", %{"wotex:bleMode" => Atom.to_string(mode)})
      owner = start_supervised!(subscription_spec(consumed, kind, self()))

      SoftwarePeer.wait_until(
        fn -> SoftwarePeer.command("stats")["notification_sessions"] == 1 end,
        5000
      )

      refute_receive {:wotex_runtime, _, {:ok, _, _}}, 50

      for _ <- 1..2 do
        SoftwarePeer.command("value", %{label: Atom.to_string(mode), hex: "01", emit: true})
        assert_receive {:wotex_runtime, _, {:ok, 1, metadata}}, 1000
        assert metadata.source == :bluez_value_change
        assert metadata.characteristic.service_uuid == SoftwarePeer.service()
        assert metadata.characteristic.characteristic_uuid == SoftwarePeer.uuid(mode)
        assert metadata.requested_mode == mode
        assert metadata.effective_mode == mode
        refute is_struct(metadata.characteristic)
      end

      assert :ok = Subscription.stop(owner)
      SoftwarePeer.wait_until(&SoftwarePeer.released?/0)
      refute_receive {:wotex_runtime, _, {:ok, _, _}}, 30
    end

    assert SoftwarePeer.command("stats")["confirms"] == 4
  end

  test "WBL-I05 final receiver death closes the real Runtime native sender within its ownership grace",
       %{
         options: options
       } do
    consumed = consumer(options, :property, :notify, "uint8")
    receiver = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Process.exit(receiver, :kill) end)
    owner = start_supervised!(subscription_spec(consumed, :property, receiver))

    SoftwarePeer.wait_until(
      fn -> SoftwarePeer.command("stats")["notification_sessions"] == 1 end,
      5000
    )

    monitor = Process.monitor(owner)
    started = System.monotonic_time(:millisecond)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :receiver_down}}, 1000
    SoftwarePeer.wait_until(&SoftwarePeer.released?/0)
    assert System.monotonic_time(:millisecond) - started <= 1100
  end

  test "WBL-I05 original native stream closes after changed stop route and credential rejection", %{
    options: options
  } do
    consumed = consumer(options, :property, :notify, "uint8", %{}, nil, :reject_stop)
    owner = start_supervised!(subscription_spec(consumed, :property, self()))

    SoftwarePeer.wait_until(
      fn -> SoftwarePeer.command("stats")["notification_sessions"] == 1 end,
      5000
    )

    SoftwarePeer.command("value", %{label: "notify", hex: "01", emit: true})
    assert_receive {:wotex_runtime, _, {:ok, 1, _}}, 1000
    assert {:error, %{phase: :credentials}} = Subscription.stop(owner)
    SoftwarePeer.wait_until(&SoftwarePeer.released?/0)
    stats = SoftwarePeer.command("stats")
    assert stats["calls"]["StartNotify"] == 1
    assert stats["calls"]["StopNotify"] == 1
  end

  defp consumer(options, kind, label, type, fields \\ %{}, operations \\ nil, credentials \\ nil) do
    start = if kind == :property, do: "observeproperty", else: "subscribeevent"
    stop = if kind == :property, do: "unobserveproperty", else: "unsubscribeevent"

    form =
      Map.merge(
        %{
          "href" => "ble://peer/#{SoftwarePeer.service()}/#{SoftwarePeer.uuid(label)}",
          "op" => operations || [start, stop],
          "wotex:bleValueType" => type
        },
        fields
      )

    forms =
      if credentials == :reject_stop,
        do: [
          %{form | "op" => start},
          %{
            form
            | "op" => stop,
              "href" => "ble://changed/#{SoftwarePeer.service()}/#{SoftwarePeer.uuid(:value)}"
          }
        ],
        else: [form]

    affordance =
      if kind == :property, do: %{"forms" => forms, "observable" => true}, else: %{"forms" => forms}

    key = if kind == :property, do: "properties", else: "events"

    assert {:ok, td} =
             Wotex.ThingDescription.from_map(%{
               "@context" => "https://www.w3.org/2022/wot/td/v1.1",
               "title" => "Virtual GATT software Thing",
               "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
               "security" => ["none"],
               key => %{"reading" => affordance}
             })

    assert {:ok, profile} = BLE.profile(:gatt)

    assert {:ok, consumed} =
             ConsumedThing.new(td,
               profiles: [profile],
               credentials: {Wotex.BLE.RuntimeErrorPort, credentials},
               transports: %{ble_gatt: {Transport, Keyword.put(options, :target, "peer")}}
             )

    consumed
  end

  defp subscription_spec(consumed, kind, receiver) do
    context = Context.new!(request_id: "gatt-software-stream")

    options = [
      id: make_ref(),
      receiver: receiver,
      restart: :temporary,
      max_queue_length: 1000,
      overflow: :stop
    ]

    assert {:ok, spec} =
             if(kind == :property,
               do: ConsumedThing.observation_child_spec(consumed, "reading", context, options),
               else:
                 ConsumedThing.event_subscription_child_spec(consumed, "reading", context, options)
             )

    spec
  end
end
