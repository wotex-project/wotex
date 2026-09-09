defmodule Wotex.CoAP.Test.ErrorTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  @impl Wotex.Runtime.Transport
  def request(_, _, error), do: {:error, error}

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, :unexpected_subscription}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, :unexpected_subscription}
end
