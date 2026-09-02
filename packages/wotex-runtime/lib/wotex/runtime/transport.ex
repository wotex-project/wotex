defmodule Wotex.Runtime.Transport do
  @moduledoc """
  Port implemented by a protocol binding or consumer transport.

  Subscription transports send `{:wotex_transport, payload}` to the supplied
  receiver. Long-lived connection ownership remains with the implementation.
  """

  alias Wotex.Runtime.{ExecutionContext, Request, Result}

  @type config :: term()
  @type handle :: term()

  @callback request(Request.t(), ExecutionContext.t(), config()) ::
              {:ok, Result.t()} | {:error, term()}

  @callback subscribe(Request.t(), pid(), ExecutionContext.t(), config()) ::
              {:ok, handle()} | {:error, term()}

  @callback unsubscribe(handle(), Request.t(), ExecutionContext.t(), config()) ::
              :ok | {:error, term()}
end
