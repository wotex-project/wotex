defmodule Wotex.Thread.OpenThread.StreamOwner do
  @moduledoc """
  Admits validated State reports for one native subscription.

  The connection starts this process only after the host has registered the
  subscription. For each report it checks the final receiver's mailbox against
  the subscription's `max_queue_length` and returns the report's opaque token
  with the admission result. The connection remains the only sender of public
  deliveries, rechecks capacity before delivering, and acknowledges native
  credit only after admission. While this process is suspended, the report
  stays unacknowledged, so the native host stops transmitting for the stream.

  The owner monitors its connection and exits when that connection exits.
  Loading this module starts no process.
  """

  use GenServer

  @doc false
  @spec start(pid(), reference(), pid(), pos_integer()) :: GenServer.on_start()
  def start(connection, reference, receiver, queue_limit),
    do: GenServer.start(__MODULE__, {connection, reference, receiver, queue_limit})

  @impl GenServer
  def init({connection, reference, receiver, queue_limit}) do
    monitor = Process.monitor(connection)

    {:ok,
     %{
       connection: connection,
       monitor: monitor,
       reference: reference,
       receiver: receiver,
       queue_limit: queue_limit
     }}
  end

  @impl GenServer
  def handle_info(
        {:wotex_thread_report, connection, reference, sequence, token},
        %{connection: connection, reference: reference} = state
      ) do
    admission =
      case Process.info(state.receiver, :message_queue_len) do
        {:message_queue_len, length} when length < state.queue_limit -> :ok
        _ -> :receiver_overflow
      end

    send(connection, {:wotex_thread_report_admitted, self(), reference, sequence, token, admission})
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, Map.take(state, [:queue_limit])}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      entry -> entry
    end)
  end
end
