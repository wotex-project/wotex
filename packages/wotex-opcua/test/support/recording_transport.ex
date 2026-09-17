defmodule Wotex.OPCUA.TestRecordingTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport
  alias Wotex.OPCUA.Transport

  # Reports the Runtime-selected request, then delegates to the production Transport.
  @impl Wotex.Runtime.Transport
  def request(request, execution, config) do
    send(Keyword.fetch!(config, :test), {:runtime_request, request})
    Transport.request(request, execution, config)
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, execution, config),
    do: Transport.subscribe(request, owner, execution, config)

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, execution, config),
    do: Transport.unsubscribe(handle, request, execution, config)
end
