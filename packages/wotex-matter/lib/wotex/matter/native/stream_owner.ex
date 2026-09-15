defmodule Wotex.Matter.Native.StreamOwner do
  @moduledoc """
  Validates report admission for one ordinary native subscription.

  This internal process starts only after the connection admits a subscription.
  It validates each bound report's path and typed value, checks receiver capacity,
  and returns the report's opaque token to the connection. The connection remains
  the sole sender of public deliveries and terminal messages and checks capacity
  again before delivery. Native credit remains occupied while this owner is
  suspended. The native credit ledger bounds reports awaiting admission.

  The owner is linked to its connection and is explicitly terminated when the
  subscription retires. Loading this module starts no process or protocol I/O.
  """

  use GenServer

  alias Wotex.Matter.{Address, Descriptor}
  alias Wotex.Matter.Native.Delivery

  @doc false
  @spec start_link(pid(), binary(), reference(), pid(), map()) :: GenServer.on_start()
  def start_link(connection, generation, reference, receiver, request) do
    GenServer.start_link(__MODULE__, %{
      connection: connection,
      generation: generation,
      reference: reference,
      receiver: receiver,
      kind: request.kind,
      paths: request.paths,
      queue_limit: request.queue_limit
    })
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_info(
        {:wotex_matter, reference,
         %Delivery{connection: connection, generation: generation, reference: reference} = report},
        %{connection: connection, generation: generation, reference: reference} = state
      ) do
    admission = admit(report.value, state)

    send(
      connection,
      {:native_report_admitted, self(), generation, reference, report.sequence, report.token,
       admission}
    )

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, Map.take(state, [:kind, :queue_limit])}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      entry -> entry
    end)
  end

  defp admit({:ok, value, %{kind: kind, path: path}} = delivery, %{kind: kind} = state) do
    with {:ok, address} <- Address.new(path),
         true <- Enum.any?(state.paths, &(&1 == Map.from_struct(address))),
         {:ok, _} <- Descriptor.validate_element(kind, address, :read, value) do
      case Process.info(state.receiver, :message_queue_len) do
        {:message_queue_len, length} when length < state.queue_limit -> {:ok, delivery}
        _ -> {:error, :receiver_overflow}
      end
    else
      _ -> {:error, :invalid_frame}
    end
  end

  defp admit(_, _), do: {:error, :invalid_frame}
end
