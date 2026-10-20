defmodule Wotex.BLE.RuntimeRecordingTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  @impl Wotex.Runtime.Transport
  def request(request, execution, config) do
    send(Keyword.fetch!(config, :test_pid), {:selected_request, request})

    case Keyword.get(config, :result_override) do
      nil ->
        options =
          if Keyword.get(config, :client) == Wotex.BLE.BlueZ,
            do: Keyword.delete(config, :test_pid),
            else: config

        Wotex.BLE.Transport.request(request, execution, options)

      result ->
        {:ok, result}
    end
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, execution, config) do
    gate = Keyword.get(config, :opening_gate)

    if gate do
      {receiver, reference} = gate
      send(receiver, {reference, :opening, self()})

      receive do
        {^reference, :continue} -> :ok
      after
        5000 -> exit(:opening_gate_timeout)
      end
    end

    result =
      Wotex.BLE.Transport.subscribe(
        request,
        owner,
        execution,
        Keyword.drop(config, [:test_pid, :opening_gate])
      )

    if gate do
      {receiver, reference} = gate
      send(receiver, {reference, :opened, result})
    end

    result
  end

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, execution, config) do
    send(
      Keyword.fetch!(config, :test_pid),
      {:runtime_unsubscribe, handle, request, execution.credential == nil}
    )

    Wotex.BLE.Transport.unsubscribe(handle, request, execution, config)
  end

  @impl Wotex.Runtime.Transport
  def decode_frame(frame, request, config) do
    send(Keyword.fetch!(config, :test_pid), {:runtime_decode, self(), frame, request})
    Wotex.BLE.Transport.decode_frame(frame, request, config)
  end
end
