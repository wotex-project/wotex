defmodule Wotex.BACnet.COVListener do
  @moduledoc false

  use GenServer
  alias BACnet.Protocol.APDU
  alias BACnet.Stack.Client
  alias Wotex.BACnet.{COV, Error}

  @doc false
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl GenServer
  def init(options) do
    reference = make_ref()
    request = %{options.request | max_queue_length: 1000}

    pending =
      :gen_server.send_request(
        options.client,
        {:wotex_client, :register_cov, request, options.destination, options.deadline}
      )

    {:ok,
     Map.merge(options, %{
       pending: pending,
       owner_monitor: Process.monitor(options.owner),
       client_monitor: Process.monitor(options.client),
       token: reference,
       timer: Process.send_after(self(), {:deadline, reference}, max(options.deadline - now(), 0))
     })}
  end

  @impl GenServer
  def handle_cast(:close, state), do: {:stop, :normal, state}
  def handle_cast(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_info({:deadline, reference}, %{token: reference, pending: pending} = state)
      when pending != nil do
    fail(state, Error.new(:deadline_exceeded))
  end

  def handle_info({:DOWN, reference, :process, _, _}, %{owner_monitor: reference} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, reference, :process, _, _}, %{client_monitor: reference} = state),
    do: fail(state, Error.new(:connection_closed))

  def handle_info({:wotex_cov_error, code}, state) when code in [:slow_consumer],
    do: fail(state, Error.new(code))

  def handle_info(
        {:bacnet_client, ref, apdu, {source, _, _}, client},
        %{client: client, destination: source, pending: nil} = state
      ) do
    with {:ok, report} <- COV.notification(apdu),
         {:ok, value} <- COV.value(report, state.request),
         true <- available?(state.owner),
         :ok <- acknowledge(client, ref, report) do
      send(state.owner, {:cov_report, self(), report, value})
      {:noreply, state}
    else
      false -> fail(state, Error.new(:slow_consumer))
      {:error, %Error{} = error} -> fail(state, error)
      _ -> fail(state, Error.new(:acknowledgment_failed))
    end
  end

  def handle_info(message, %{pending: pending} = state) when pending != nil do
    case :gen_server.check_response(message, pending) do
      {:reply, {:ok, identifier}} when is_integer(identifier) and identifier in 0..4_294_967_295 ->
        Process.cancel_timer(state.timer)
        send(state.owner, {:cov_listener, self(), identifier})
        {:noreply, %{state | pending: nil, timer: nil}}

      {:reply, {:error, %Error{} = error}} ->
        fail(state, error)

      {:reply, _} ->
        fail(state, Error.new(:invalid_transport_return))

      {:error, _} ->
        fail(state, Error.new(:connection_closed))

      :no_reply ->
        {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    if state.pending, do: :gen_server.receive_response(state.pending, 0)
    request = :gen_server.send_request(state.client, {:wotex_client, :unregister_cov})
    :gen_server.receive_response(request, 0)
    :ok
  end

  defp acknowledge(client, reference, %{confirmed: true, invoke_id: id}) do
    Client.reply(client, reference, %APDU.SimpleACK{
      invoke_id: id,
      service: :confirmed_cov_notification
    })
  rescue
    _ -> {:error, Error.new(:acknowledgment_failed)}
  catch
    :exit, _ -> {:error, Error.new(:acknowledgment_failed)}
  end

  defp acknowledge(_, _, _), do: :ok

  defp fail(state, error) do
    send(state.owner, {:cov_listener_error, self(), error})
    {:stop, :normal, state}
  end

  defp available?(owner) do
    case Process.info(owner, :message_queue_len) do
      {:message_queue_len, length} -> length < 1000
      nil -> false
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
