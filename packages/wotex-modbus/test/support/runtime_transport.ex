defmodule Wotex.Modbus.RuntimeTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport
  alias Wotex.Modbus.Transport
  alias Wotex.Runtime.Result

  @impl Wotex.Runtime.Transport
  def request(request, execution, {:record, receiver, options}) do
    send(receiver, {:runtime_request, request})
    {:links, before} = Process.info(self(), :links)
    result = Transport.request(request, execution, options)
    {:links, after_links} = Process.info(self(), :links)
    send(receiver, {:runtime_resources, after_links -- before})
    result
  end

  def request(_request, _execution, {:fault, error}), do: {:error, error}

  def request(request, _execution, {:result, payload, changes}) do
    {:ok, result} = Result.new(request.request_id, request.operation, payload)
    {:ok, struct!(result, changes)}
  end

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, :unexpected_subscription}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, :unexpected_subscription}
end
