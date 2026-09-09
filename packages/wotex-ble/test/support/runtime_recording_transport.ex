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
  def subscribe(request, owner, execution, config),
    do: Wotex.BLE.Transport.subscribe(request, owner, execution, Keyword.delete(config, :test_pid))

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
