defmodule Wotex.Matter.SoftwareControlPump do
  @moduledoc false

  import ExUnit.Assertions

  alias Wotex.Matter.{Address, Descriptor}
  alias Wotex.Matter.Native.Wire

  @spec new(binary(), map(), map()) :: map()
  def new(session, established, path) do
    {:ok, address} = Address.new(path)

    %{
      session: session,
      subscription: established["subscription_id"],
      generation: established["generation"],
      sdk_id: established["sdk_subscription_id"],
      minimum: established["min_interval_s"],
      maximum: established["max_interval_s"],
      address: address,
      sequence: 0,
      bytes: 0,
      report_id: 0,
      pending_frames: 0,
      pending_bytes: 0
    }
  end

  @spec report!(map(), map(), pos_integer()) :: map()
  def report!(probe, frame, bytes) do
    assert is_map(frame) and map_size(frame) == 9
    assert frame["version"] == 1
    assert frame["event"] == "subscription_report"
    assert frame["session_generation"] == probe.session
    assert frame["subscription_id"] == probe.subscription
    assert frame["generation"] == probe.generation
    assert frame["report_sequence"] == probe.sequence + 1

    assert {:ok, {:ok, value, metadata}} =
             Wire.subscription(frame["kind"], frame["value"], frame["metadata"])

    assert metadata.kind == :attribute
    assert metadata.path == probe.address
    assert metadata.sdk_subscription_id == probe.sdk_id
    assert metadata.min_interval_s == probe.minimum
    assert metadata.max_interval_s == probe.maximum
    assert {:ok, ^value} = Descriptor.validate_element(:attribute, probe.address, :read, value)
    assert metadata.report_id > probe.report_id
    assert probe.pending_frames < 64
    assert bytes in 1..131_072
    assert probe.pending_bytes + bytes <= 1_048_576

    %{
      probe
      | sequence: frame["report_sequence"],
        bytes: probe.bytes + bytes,
        report_id: metadata.report_id,
        pending_frames: probe.pending_frames + 1,
        pending_bytes: probe.pending_bytes + bytes
    }
  end

  @spec pending!(port(), map(), pos_integer()) :: map()
  def pending!(port, probe, timeout),
    do: wait(port, probe, System.monotonic_time(:millisecond) + timeout, :pending)

  @spec retired!(port(), map(), pos_integer()) :: map()
  def retired!(port, probe, timeout),
    do: wait(port, probe, System.monotonic_time(:millisecond) + timeout, :retired)

  @spec acknowledge!(port(), map()) :: map()
  def acknowledge!(port, probe) do
    frame = %{
      version: 1,
      event: "report_ack",
      session_generation: probe.session,
      report_sequence: probe.sequence,
      acknowledged_bytes: probe.bytes
    }

    assert Port.command(port, Jason.encode!(frame) <> "\n", [:nosuspend])
    %{probe | pending_frames: 0, pending_bytes: 0}
  end

  defp wait(port, probe, deadline, mode) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      if mode == :pending, do: probe, else: flunk("native retirement deadline expired")
    else
      receive do
        {^port, {:data, {:eol, bytes}}} ->
          assert {:ok, frame} = Wire.frame(bytes)

          if mode == :retired and frame["event"] == "stream_retired" do
            assert System.monotonic_time(:millisecond) < deadline

            assert frame == %{
                     "version" => 1,
                     "event" => "stream_retired",
                     "session_generation" => probe.session,
                     "subscription_id" => probe.subscription,
                     "generation" => probe.generation,
                     "last_report_sequence" => probe.sequence
                   }

            probe
          else
            wait(port, report!(probe, frame, byte_size(bytes) + 1), deadline, mode)
          end

        {^port, _} ->
          flunk("native control channel closed or exceeded its frame limit")
      after
        remaining -> wait(port, probe, deadline, mode)
      end
    end
  end
end
