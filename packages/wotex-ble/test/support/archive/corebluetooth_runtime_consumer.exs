Code.require_file("corebluetooth_support.exs", __DIR__)

defmodule CoreArchiveCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials
  @impl Wotex.Runtime.Credentials
  def resolve(%{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}}, _, _, _),
    do: {:ok, nil}

  def resolve(_, _, _, _), do: {:error, :unsupported_security}
end

defmodule CoreArchiveTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport
  @impl Wotex.Runtime.Transport
  def request(request, execution, options) do
    result = Wotex.BLE.Transport.request(request, execution, Keyword.delete(options, :observer))
    send(Keyword.fetch!(options, :observer), {:core_transport_result, request.request_id, result})
    result
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, execution, options) do
    send(Keyword.fetch!(options, :observer), {:core_request, request})
    Wotex.BLE.Transport.subscribe(request, owner, execution, Keyword.delete(options, :observer))
  end

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, execution, options),
    do:
      Wotex.BLE.Transport.unsubscribe(
        handle,
        request,
        execution,
        Keyword.delete(options, :observer)
      )

  @impl Wotex.Runtime.Transport
  def decode_frame(frame, request, options),
    do: Wotex.BLE.Transport.decode_frame(frame, request, Keyword.delete(options, :observer))
end

defmodule CoreRuntimeArchiveTest do
  @moduledoc false

  use ExUnit.Case, async: false
  import CoreArchiveSupport
  alias Wotex.{BLE, ThingDescription}
  alias Wotex.BLE.CoreBluetooth
  alias Wotex.Runtime.{ConsumedThing, Context, Subscription}
  @accepted %{write_mode: :without_response, evidence: :native_queue_accepted}

  test "real Runtime point Results retain codecs, exact write mode and accepted status" do
    for {selector, operation, payload, status} <- [
          {%{"wotex:bleValueType" => "uint16"}, :read, 65_280, :ok},
          {%{}, :write, :written, :ok},
          {%{"wotex:bleWriteMode" => "without_response"}, :write, @accepted, :accepted}
        ] do
      {options, path} = fixture("normal")
      consumed = consumer(options, selector)

      context =
        Context.new!(
          request_id: "archive:point",
          deadline: System.monotonic_time(:millisecond) + 3000
        )

      result =
        if operation == :read,
          do: ConsumedThing.read_property(consumed, "value", context),
          else: ConsumedThing.write_property(consumed, "value", <<1, 2>>, context)

      assert {:ok, %{request_id: "archive:point", payload: ^payload, status: ^status}} = result

      op =
        if payload == @accepted,
          do: "write_command",
          else: if(operation == :read, do: "read", else: "write")

      assert Enum.count(records(path), &(&1["operation"] == op)) == 1
      assert List.last(records(path))["operation"] == "close"
      eventually(fn -> gone?(pid(path)) end)
    end
  end

  test "Property and Event streams preserve equal typed updates and close their private native session" do
    for kind <- [:property, :event] do
      {options, path} = fixture("normal")
      owner = start_stream(consumer(options, %{}, kind), kind, self())
      assert_receive {:core_request, request}, 2000
      assert request.operation == if(kind == :property, do: :observeproperty, else: :subscribeevent)

      for _ <- 1..3 do
        assert_receive {:wotex_runtime, _, {:ok, 65_280, metadata}}, 2000
        assert metadata.source == :corebluetooth_value_update
        assert metadata.effective_mode == :notify and metadata.requested_mode == :auto
        assert metadata.characteristic.generation == 7 and metadata.characteristic.route == 3
      end

      assert :ok = Subscription.stop(owner)
      assert Enum.count(records(path), &(&1["operation"] == "open")) == 1
      assert List.last(records(path))["operation"] == "close"
      eventually(fn -> gone?(pid(path)) end)
    end
  end

  test "target, security, selector and caller-deadline refusal acquire no native process" do
    for change <- [[target: "other"], [security_mode: :authenticated]] do
      {options, path} = fixture("normal")

      assert {:error, _} =
               ConsumedThing.read_property(
                 consumer(Keyword.merge(options, change)),
                 "value",
                 Context.new!(request_id: "denied")
               )

      refute File.exists?(path <> ".trace")
    end

    for selector <- [
          %{"wotex:bleWriteMode" => "without_response"},
          %{"wotex:bleValueType" => "guess"}
        ] do
      {options, path} = fixture("normal")

      assert {:error, _} =
               ConsumedThing.read_property(
                 consumer(options, selector),
                 "value",
                 Context.new!(request_id: "selector")
               )

      refute File.exists?(path <> ".trace")
    end

    {options, path} = fixture("normal")
    expired = Context.new!(request_id: "expired", deadline: System.monotonic_time(:millisecond) - 1)
    assert {:error, _} = ConsumedThing.write_property(consumer(options), "value", <<1>>, expired)
    refute File.exists?(path <> ".trace")
  end

  test "native command failures retain conservative Runtime errors without replay" do
    for mode <- ~w(command-ack missing-marker post-error sleep-write) do
      {options, path} = fixture(mode)
      consumed = consumer(options, %{"wotex:bleWriteMode" => "without_response"})

      assert {:error, error} =
               ConsumedThing.write_property(
                 consumed,
                 "value",
                 <<1>>,
                 Context.new!(request_id: "failed")
               )

      assert_receive {:core_transport_result, "failed", {:error, %BLE.Error{effect: :unknown}}}
      assert error.class == :permanent
      refute Map.has_key?(error.details.cause, :effect)

      assert :stop =
               Wotex.Runtime.Retry.decision(:writeproperty, error,
                 attempt: 1,
                 max_attempts: 2,
                 idempotent?: true
               )

      assert Enum.count(records(path), &(&1["operation"] == "write_command")) == 1
      eventually(fn -> gone?(pid(path)) end)
    end
  end

  test "the public decoder refuses native metadata under another backend" do
    {options, _} = fixture("normal")
    owner = start_stream(consumer(options, %{}, :property), :property, self())
    assert_receive {:core_request, request}, 2000
    assert_receive {:wotex_runtime, _, {:ok, 65_280, metadata}}, 2000

    assert {:ok, 65_280, ^metadata} =
             BLE.Transport.decode_frame({:value, <<0, 255>>, metadata}, request,
               client: CoreBluetooth
             )

    assert {:error, %BLE.Error{code: :invalid_response}} =
             BLE.Transport.decode_frame({:value, <<0, 255>>, metadata}, request,
               client: Wotex.BLE.BlueZ
             )

    assert {:error, %BLE.Error{code: :invalid_response}} =
             BLE.Transport.decode_frame(
               {:value, <<0, 255>>, Map.put(metadata, :extra, true)},
               request,
               client: CoreBluetooth
             )

    assert :ok = Subscription.stop(owner)
  end

  @tag capture_log: true
  test "independent Runtime owners and receiver death release only their original native instances" do
    for loss <- [:receiver, :owner] do
      {first_options, first_path} = fixture("silent")
      {second_options, second_path} = fixture("silent")
      receiver = spawn(fn -> receive do: (:finish -> :ok) end)
      on_exit(fn -> Process.exit(receiver, :kill) end)
      first = start_stream(consumer(first_options, %{}, :property), :property, receiver)
      second = start_stream(consumer(second_options, %{}, :event), :event, self())
      eventually(fn -> Enum.any?(records(first_path), &(&1["operation"] == "subscribe")) end)
      eventually(fn -> Enum.any?(records(second_path), &(&1["operation"] == "subscribe")) end)
      assert pid(first_path) != pid(second_path)
      Process.exit(if(loss == :receiver, do: receiver, else: first), :kill)
      eventually(fn -> gone?(pid(first_path)) end)
      assert Process.alive?(second)
      refute gone?(pid(second_path))
      assert :ok = Subscription.stop(second)
      eventually(fn -> gone?(pid(second_path)) end)
    end
  end

  test "incompatible startup, stream bindings and bytes cannot become Runtime values" do
    for mode <- ~w(bad-ready bad-binding bad-value) do
      {options, path} = fixture(mode)
      owner = start_stream(consumer(options, %{}, :property), :property, self())
      assert_receive {:wotex_runtime, _, {:error, %Wotex.Runtime.Error{}}}, 2500
      refute_received {:wotex_runtime, _, {:ok, _, _}}
      if Process.alive?(owner), do: Subscription.stop(owner)
      eventually(fn -> gone?(pid(path)) end)
    end
  end

  defp start_stream(consumed, kind, receiver) do
    context =
      Context.new!(
        request_id: "archive:stream",
        deadline: System.monotonic_time(:millisecond) + 3000
      )

    options = [id: make_ref(), receiver: receiver, restart: :temporary, max_queue_length: 1000]

    {:ok, spec} =
      if kind == :property,
        do: ConsumedThing.observation_child_spec(consumed, "value", context, options),
        else: ConsumedThing.event_subscription_child_spec(consumed, "value", context, options)

    start_supervised!(spec)
  end

  defp consumer(options, fields \\ %{}, kind \\ :point) do
    form = Map.merge(%{"href" => "ble://route/181a/2a19"}, fields)

    {key, affordance} =
      case kind do
        :point ->
          {"properties", %{"forms" => [form]}}

        :property ->
          {"properties",
           %{
             "observable" => true,
             "forms" => [
               Map.merge(form, %{
                 "op" => ["observeproperty", "unobserveproperty"],
                 "wotex:bleValueType" => "uint16"
               })
             ]
           }}

        :event ->
          {"events",
           %{
             "forms" => [
               Map.merge(form, %{
                 "op" => ["subscribeevent", "unsubscribeevent"],
                 "wotex:bleValueType" => "uint16"
               })
             ]
           }}
      end

    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Independent archive Runtime consumer",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        key => %{"value" => affordance}
      })

    profile = if kind == :point, do: BLE.profile(), else: elem(BLE.profile(:gatt), 1)
    config = Keyword.merge([client: CoreBluetooth, target: "route", observer: self()], options)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        credentials: {CoreArchiveCredentials, nil},
        transports: %{profile.id => {CoreArchiveTransport, config}}
      )

    consumed
  end
end
