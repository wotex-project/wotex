defmodule Wotex.BACnet.Test.IntegrationTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport
  alias Wotex.BACnet.Transport

  @impl Wotex.Runtime.Transport
  def request(request, context, config) do
    send(Keyword.fetch!(config, :observer), {:runtime_request, request})
    outcome = Transport.request(request, context, Keyword.delete(config, :tamper))

    case {outcome, Keyword.get(config, :tamper)} do
      {{:ok, result}, :request_id} -> {:ok, %{result | request_id: "foreign-request"}}
      {{:ok, result}, :operation} -> {:ok, %{result | operation: :writeproperty}}
      _ -> outcome
    end
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, context, config),
    do: Transport.subscribe(request, owner, context, config)

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, context, config),
    do: Transport.unsubscribe(handle, request, context, config)
end
