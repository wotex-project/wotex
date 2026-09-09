defmodule Wotex.CoAP.Test.RuntimeCapture do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  @impl Wotex.Runtime.Transport
  def request(request, execution, {receiver, options}) do
    send(receiver, {:selected_request, request})
    send(receiver, {:callback_owner, self()})
    Wotex.CoAP.Transport.request(request, execution, options)
  end

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, :unexpected_subscription}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, :unexpected_subscription}
end
