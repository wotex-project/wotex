defmodule Wotex.OPCUA.TestFailureTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport
  alias Wotex.OPCUA.Error

  # The configured native failure passes through the production classifier.
  @impl Wotex.Runtime.Transport
  def request(_, _, %{code: code, effect: effect}),
    do: {:error, Error.classify(%{Error.new(code) | effect: effect})}

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, Error.classify(Error.new(:unsupported_operation))}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: :ok
end
