defmodule Wotex.Runtime.Test.FakeTransport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  alias Wotex.Runtime.Result

  defmodule ExternalError do
    @moduledoc false
    defstruct [:code, :phase, :class, message: "external"]
  end

  @impl Wotex.Runtime.Transport
  def request(request, execution_context, %{test_pid: test_pid} = config) do
    send(
      test_pid,
      {:request, request, execution_context.context.request_id, execution_context.credential}
    )

    case Map.get(config, :mode, :ok) do
      :ok ->
        Result.new(request.request_id, request.operation, request.input,
          status: :ok,
          metadata: %{binding: :fake, http: %{status: 200}}
        )

      :mismatch ->
        Result.new("another-request", request.operation, nil)

      :error ->
        {:error, {:transport_error, execution_context.credential}}

      :classified_error ->
        {:error, %ExternalError{code: :http_status, phase: :response, class: :rate_limited}}

      :raise ->
        raise ArgumentError, "adapter defect #{execution_context.credential}"

      :exit ->
        exit({:adapter_exit, execution_context.credential})

      :invalid ->
        :invalid
    end
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, receiver, execution_context, %{test_pid: test_pid} = config) do
    send(
      test_pid,
      {:subscribe, request, receiver, execution_context.credential}
    )

    case Map.get(config, :subscribe_mode, :ok) do
      :ok ->
        {:ok, make_ref()}

      :linked ->
        connection = spawn_link(fn -> connection_loop(receiver) end)
        send(test_pid, {:connection, connection})
        {:ok, connection}

      :error ->
        {:error, {:subscribe_error, execution_context.credential}}

      :raise ->
        raise ArgumentError, "adapter defect #{execution_context.credential}"

      :invalid ->
        :invalid
    end
  end

  @impl Wotex.Runtime.Transport
  def decode_frame(frame, request, %{test_pid: test_pid}) do
    send(test_pid, {:decode_frame, frame, request.operation, self()})

    case frame do
      {:value, value} -> {:ok, value, %{topic: "fake/topic"}}
      :keepalive -> :ignore
      :bad -> {:error, %ExternalError{code: :codec_failure, phase: :codec, class: :protocol}}
      _other -> :invalid
    end
  end

  defp connection_loop(owner) do
    receive do
      {:deliver, value} ->
        send(owner, {:wotex_transport, {:ok, value, %{}}})
        connection_loop(owner)

      :crash ->
        exit(:connection_reset)
    end
  end

  @impl Wotex.Runtime.Transport
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
