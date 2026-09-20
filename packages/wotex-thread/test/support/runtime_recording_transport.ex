defmodule Wotex.Thread.RuntimeRecordingTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  @impl Wotex.Runtime.Transport
  def request(request, execution, config) do
    send(Keyword.fetch!(config, :test_pid), {:selected_request, request})

    case Keyword.fetch(config, :result_override) do
      {:ok, result} -> {:ok, result}
      :error -> Wotex.Thread.Transport.request(request, execution, config)
    end
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, execution, config),
    do: Wotex.Thread.Transport.subscribe(request, owner, execution, config)

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, execution, config),
    do: Wotex.Thread.Transport.unsubscribe(handle, request, execution, config)
end
