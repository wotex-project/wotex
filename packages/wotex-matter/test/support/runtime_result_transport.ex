defmodule Wotex.Matter.RuntimeResultTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  alias Wotex.Runtime.{Limits, Result}

  @impl Wotex.Runtime.Transport
  def request(request, _, %{mode: mode, test_pid: test_pid}) do
    send(test_pid, {:result_transport_request, request.request_id, request.operation})
    result(mode, request)
  end

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, Wotex.Matter.Error.new(:not_supported)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: :ok

  defp result(:wrong_identity, request),
    do: Result.new("another-request", request.operation, nil)

  defp result(:wrong_operation, request),
    do: Result.new(request.request_id, :writeproperty, nil)

  defp result(:maximum_metadata, request) do
    metadata = Map.new(1..Limits.maximum(:metadata_entries), &{&1, &1})
    Result.new(request.request_id, request.operation, nil, metadata: metadata)
  end

  defp result(:oversized_metadata, request) do
    metadata = Map.new(1..(Limits.maximum(:metadata_entries) + 1), &{&1, &1})

    {:ok,
     %Result{
       request_id: request.request_id,
       operation: request.operation,
       status: :ok,
       payload: nil,
       metadata: metadata
     }}
  end
end
