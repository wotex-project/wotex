defmodule Wotex.BACnet.Test.IntegrationTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport
  alias Wotex.BACnet.Transport

  @impl Wotex.Runtime.Transport
  def request(request, context, config) do
    send(Keyword.fetch!(config, :observer), {:runtime_request, request})
    Transport.request(request, context, config)
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, context, config),
    do: Transport.subscribe(request, owner, context, config)

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, context, config),
    do: Transport.unsubscribe(handle, request, context, config)
end
