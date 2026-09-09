defmodule Wotex.Modbus.TelemetryTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Modbus
  alias Wotex.Modbus.{Error, TestPeer}

  @event [:wotex, :modbus, :request, :stop]

  setup do
    handler = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(handler, @event, &__MODULE__.record/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
  end

  test "WMB-C08 WMB-V12 values and exceptional responses never enter telemetry metadata" do
    canary = 0xCAFE

    for {response, expected} <- [
          {<<6, 0, 17, canary::16>>, :ok},
          {<<0x86, 2>>, :error},
          {<<0x86, 2, "payload-and-exception-canary">>, :error}
        ] do
      {peer, port} = TestPeer.start(fn _, _, <<6, 0, 17, ^canary::16>> -> response end)
      {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
      result = Modbus.write_holding_register(session, 17, canary)
      assert if(expected == :ok, do: result == :ok, else: match?({:error, %Error{}}, result))

      assert_receive {:telemetry, @event, measurements, metadata}, 1000
      assert Map.keys(measurements) == [:duration]
      assert is_integer(measurements.duration) and measurements.duration >= 0
      assert metadata == %{function: 6, result: expected}
      assert :ok = Modbus.disconnect(session)
      assert :ok = Task.await(peer)
    end

    refute_received {:telemetry, _, _, _}
  end

  test "WMB-C08 startup and credential rejection emit no fabricated completed request event" do
    {:ok, listener} = :gen_tcp.listen(0, active: false, ip: {127, 0, 0, 1})
    {:ok, {_, port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)

    assert {:error, %Error{code: :connect_failed}} =
             Modbus.connect(host: "127.0.0.1", port: port)

    assert {:error, %Error{}} =
             Modbus.connect(
               host: "hostname-canary.invalid",
               credentials: "credential-canary",
               password: "password-canary"
             )

    refute_received {:telemetry, _, _, _}
  end

  @doc false
  @spec record([atom()], map(), map(), pid()) :: term()
  def record(event, measurements, metadata, receiver) do
    send(receiver, {:telemetry, event, measurements, metadata})
  end
end
