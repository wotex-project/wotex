defmodule Wotex.BLE.RuntimeRecordingTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  @impl Wotex.Runtime.Transport
  def request(request, execution, config) do
    send(Keyword.fetch!(config, :test_pid), {:selected_request, request})

    case Keyword.get(config, :result_override) do
      nil -> Wotex.BLE.Transport.request(request, execution, config)
      result -> {:ok, result}
    end
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, execution, config),
    do: Wotex.BLE.Transport.subscribe(request, owner, execution, config)

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, execution, config),
    do: Wotex.BLE.Transport.unsubscribe(handle, request, execution, config)
end
