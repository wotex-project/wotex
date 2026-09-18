defmodule Wotex.Runtime.Bench.EchoTransport do
  @moduledoc false

  # An in-process transport and credential port. `request/3` answers at once
  # with a Result that echoes the request input, so a benchmark measures the
  # Runtime path (selection, request construction, credential resolution,
  # port isolation and result validation) rather than a protocol exchange.

  @behaviour Wotex.Runtime.Credentials
  @behaviour Wotex.Runtime.Transport

  alias Wotex.Runtime.{ExecutionContext, Request, Result}

  @impl Wotex.Runtime.Credentials
  @spec resolve(map(), Wotex.Form.t(), Wotex.Runtime.Context.t(), term()) :: {:ok, nil}
  def resolve(_, _, _, _), do: {:ok, nil}

  @impl Wotex.Runtime.Transport
  @spec request(Request.t(), ExecutionContext.t(), term()) ::
          {:ok, Result.t()} | {:error, Wotex.Runtime.Error.t()}
  def request(%Request{} = request, _, _) do
    Result.new(request.request_id, request.operation, request.input, status: :ok)
  end

  @impl Wotex.Runtime.Transport
  @spec subscribe(Request.t(), pid(), ExecutionContext.t(), term()) :: {:ok, reference()}
  def subscribe(_, _, _, _), do: {:ok, make_ref()}

  @impl Wotex.Runtime.Transport
  @spec unsubscribe(term(), Request.t(), ExecutionContext.t(), term()) :: :ok
  def unsubscribe(_, _, _, _), do: :ok
end
