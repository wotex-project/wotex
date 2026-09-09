defmodule Wotex.Lab.TelemetryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab
  alias Wotex.Lab.Adapters.Directory.EtsRepository
  alias Wotex.Lab.Adapters.Runtime.{Loopback, StaticRef}
  alias Wotex.Lab.Examples.{Thermal, WindowAnomaly}
  alias Wotex.Lab.Reference.Thing
  alias Wotex.Lab.Telemetry
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context}
  alias Wotex.ThingDescription

  @credential "secret-credential-9f1e"
  @payload "payload-sentinel-77aa"

  setup do
    handler = "telemetry-test-#{System.unique_integer([:positive])}"
    test = self()

    events =
      for component <- Telemetry.components(),
          operation <- Telemetry.operations(),
          event <- [:start, :stop, :exception, :measurement],
          do: [:wotex, :lab, component, operation, event]

    :ok = :telemetry.attach_many(handler, events, &__MODULE__.handle_event/4, test)

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  test "a span emits start and stop with native measurements and an allowlisted outcome" do
    assert {:ok, 1} =
             Telemetry.span(:nx, :encode, %{profile: :test, scenario_id: "s-1", ignored: 1}, fn ->
               {:ok, 1}
             end)

    assert_receive {:span, [:wotex, :lab, :nx, :encode, :start], start, metadata}
    assert is_integer(start.monotonic_time) and is_integer(start.system_time)
    assert metadata == %{profile: :test, scenario_id: "s-1"}

    assert_receive {:span, [:wotex, :lab, :nx, :encode, :stop], stop, stopped}
    assert stop.duration >= 0 and Telemetry.to_milliseconds(stop.duration) >= 0
    assert stopped.outcome == :ok

    Telemetry.span(:nx, :decode, %{}, fn -> {:error, %{code: :dtype_mismatch}} end)
    assert_receive {:span, [:wotex, :lab, :nx, :decode, :stop], _, %{outcome: :dtype_mismatch}}

    Telemetry.span(:nx, :decode, %{}, fn -> {:error, "plain"} end)
    assert_receive {:span, [:wotex, :lab, :nx, :decode, :stop], _, %{outcome: :error}}

    Telemetry.span(:nx, :decode, %{}, fn -> :ignore end)
    assert_receive {:span, [:wotex, :lab, :nx, :decode, :stop], _, %{outcome: :ignored}}
  end

  test "an exception closes the span with its kind only and propagates unchanged" do
    assert_raise ArgumentError, "boom " <> @credential, fn ->
      Telemetry.span(:policy, :dispatch, %{operation: "setTarget"}, fn ->
        raise ArgumentError, "boom " <> @credential
      end)
    end

    assert_receive {:span, [:wotex, :lab, :policy, :dispatch, :exception], measurements, metadata}
    assert measurements.duration >= 0
    assert metadata == %{operation: "setTarget", kind: :error, outcome: :exception}
    refute inspect(metadata) =~ @credential

    assert catch_throw(Telemetry.span(:policy, :dispatch, %{}, fn -> throw(:thrown) end)) == :thrown
    assert_receive {:span, [:wotex, :lab, :policy, :dispatch, :exception], _, %{kind: :throw}}
  end

  test "metadata is allowlisted and bounded; measurements keep numbers only" do
    long = String.duplicate("x", Telemetry.max_label_bytes() + 1)

    assert Telemetry.metadata(%{
             scenario_id: "ok",
             thing_ref: long,
             profile: :http,
             outcome: {:tuple, 1},
             attempt: 2,
             headers: %{"authorization" => @credential},
             td: %{"id" => "x"},
             pid: self()
           }) == %{scenario_id: "ok", profile: :http, attempt: 2}

    assert Telemetry.event(:sse, :parse, %{"bad" => 1, bytes: 10, rate: :fast}, %{profile: :http}) ==
             :ok

    assert_receive {:span, [:wotex, :lab, :sse, :parse, :measurement], %{bytes: 10} = m, _}
    refute Map.has_key?(m, :rate)

    ref = Telemetry.thing_ref("urn:wotex:lab:room:1")
    assert String.starts_with?(ref, "thing:") and byte_size(ref) == 22
    refute ref =~ "room"
    assert ref == Telemetry.thing_ref("urn:wotex:lab:room:1")
  end

  test "the forwarding handler delivers filtered events to an explicit receiver" do
    handler = "forward-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(handler, [:wotex, :lab, :nx, :encode, :stop], &Telemetry.forward/4, self())

    on_exit(fn -> :telemetry.detach(handler) end)
    assert :ok = Telemetry.span(:nx, :encode, %{profile: :forward}, fn -> :ok end)

    assert_receive {:wotex_lab_telemetry, [:wotex, :lab, :nx, :encode, :stop], %{duration: _},
                    %{profile: :forward, outcome: :ok}}
  end

  test "a raising handler is detached by telemetry and never changes a span result" do
    handler = "raising-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:wotex, :lab, :nx, :inference, :stop],
        &__MODULE__.raise_event/4,
        nil
      )

    ExUnit.CaptureLog.capture_log(fn ->
      assert 42 == Telemetry.span(:nx, :inference, %{}, fn -> 42 end)
    end)

    assert :telemetry.list_handlers([:wotex, :lab, :nx, :inference, :stop])
           |> Enum.map(& &1.id)
           |> Enum.member?(handler) == false
  end

  test "the examples and directory emit parse, encode, inference, decode and directory spans" do
    assert {:ok, _} = Thermal.run()
    assert_receive {:span, [:wotex, :lab, :scenario, :parse, :stop], _, %{outcome: :ok}}
    assert_receive {:span, [:wotex, :lab, :nx, :encode, :stop], _, %{profile: :thermal}}
    assert_receive {:span, [:wotex, :lab, :nx, :inference, :stop], _, %{profile: :thermal}}
    assert_receive {:span, [:wotex, :lab, :nx, :decode, :stop], _, %{profile: :thermal}}

    assert {:ok, _} = WindowAnomaly.run()
    assert_receive {:span, [:wotex, :lab, :nx, :decode, :stop], _, %{profile: :window_anomaly}}

    lab = start_supervised!({Lab, id: "telemetry-directory", max_children: 4})
    {:ok, repository} = Lab.start_child(lab, :things, {EtsRepository, id: :telemetry})
    context = Wotex.Directory.Context.new!(:operator)

    assert :not_found = EtsRepository.fetch(repository, "missing", context)

    assert_receive {:span, [:wotex, :lab, :directory, :directory, :stop], _,
                    %{operation: :fetch, profile: :ets, outcome: :not_found}}
  end

  test "runtime requests and dispatches carry no credential, payload or Thing id" do
    lab = start_supervised!({Lab, id: "telemetry-runtime", max_children: 4})

    {:ok, json} =
      File.read(Application.app_dir(:wotex_lab, "priv/fixtures/loopback/thing-description.json"))

    {:ok, td} = ThingDescription.parse(json)

    {:ok, host} =
      Lab.start_child(
        lab,
        :things,
        {Thing,
         td: td,
         state: %{"temperature" => 20.0, "target" => @payload},
         tokens: %{"bearer_sc" => @credential}}
      )

    {:ok, profile} =
      BindingProfile.new(
        id: :loopback,
        schemes: ["loopback"],
        operations: Wotex.Runtime.operations()
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: host}}},
        credentials:
          {StaticRef,
           %{references: %{"bearer_sc" => "ref"}, lookup: fn "ref" -> {:ok, @credential} end}}
      )

    context = Context.new!(request_id: "telemetry-read")
    assert {:ok, %{payload: @payload}} = ConsumedThing.read_property(consumed, "target", context)
    assert {:ok, _} = ConsumedThing.invoke_action(consumed, "setTarget", 21.0, context)

    assert_receive {:span, [:wotex, :lab, :runtime, :request, :start], _,
                    %{operation: :readproperty, profile: :loopback}}

    assert_receive {:span, [:wotex, :lab, :runtime, :request, :stop], _,
                    %{operation: :invokeaction, outcome: :ok}}

    for message <- flush([]) do
      text = inspect(message)
      refute text =~ @credential, "credential leaked: #{text}"
      refute text =~ @payload, "payload leaked: #{text}"
      refute text =~ "urn:wotex:lab", "thing id leaked: #{text}"
    end
  end

  test "span refuses components and operations outside the vocabulary" do
    unknown = Enum.at([:unknown], 0)
    empty_list = Enum.at([[]], 0)
    assert_raise FunctionClauseError, fn -> Telemetry.span(unknown, :encode, %{}, fn -> :ok end) end
    assert_raise FunctionClauseError, fn -> Telemetry.span(:nx, unknown, %{}, fn -> :ok end) end
    assert_raise FunctionClauseError, fn -> Telemetry.event(:nx, :encode, empty_list, %{}) end
  end

  @doc false
  def handle_event(event, measurements, metadata, test),
    do: send(test, {:span, event, measurements, metadata})

  @doc false
  def raise_event(_, _, _, _), do: raise("exporter down")

  defp flush(acc) do
    receive do
      {:span, _, _, _} = message -> flush([message | acc])
    after
      0 -> acc
    end
  end
end
