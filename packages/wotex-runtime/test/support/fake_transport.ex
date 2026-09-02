defmodule Wotex.Runtime.Test.FakeTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  alias Wotex.Runtime.Result

  @impl true
  def request(request, execution_context, %{test_pid: test_pid} = config) do
    send(
      test_pid,
      {:request, request, execution_context.context.request_id, execution_context.credential}
    )

    case Map.get(config, :mode, :ok) do
      :ok ->
        Result.new(request.request_id, request.operation, request.input,
          status: 200,
          metadata: %{binding: :fake}
        )

      :mismatch ->
        Result.new("another-request", request.operation, nil)

      :error ->
        {:error, {:transport_error, execution_context.credential}}

      :invalid ->
        :invalid
    end
  end

  @impl true
  def subscribe(request, receiver, execution_context, %{test_pid: test_pid} = config) do
    send(
      test_pid,
      {:subscribe, request, receiver, execution_context.credential}
    )

    case Map.get(config, :subscribe_mode, :ok) do
      :ok -> {:ok, make_ref()}
      :error -> {:error, {:subscribe_error, execution_context.credential}}
      :invalid -> :invalid
    end
  end

  @impl true
  def unsubscribe(handle, request, execution_context, %{test_pid: test_pid} = config) do
    send(
      test_pid,
      {:unsubscribe, handle, request, execution_context.credential}
    )

    case Map.get(config, :unsubscribe_mode, :ok) do
      :ok -> :ok
      :error -> {:error, {:unsubscribe_error, execution_context.credential}}
      :invalid -> :invalid
    end
  end
end
