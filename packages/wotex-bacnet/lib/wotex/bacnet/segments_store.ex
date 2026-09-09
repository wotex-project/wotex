defmodule Wotex.BACnet.SegmentsStore do
  @moduledoc """
  Owned reassembly process adapting BACstack 0.0.1 segment-store responses.

  `Wotex.BACnet.StackOwner` starts this process explicitly with the configured
  APDU timeout, a maximum of 32 segments, and zero APDU retries. Calls, casts,
  and timer messages delegate to the pinned SDK implementation.

  The adapter adds the cancellation flag omitted by the SDK's two-element
  error reply so the client can clean up a refused assembly. This narrow
  compatibility correction does not introduce a global segment store or change
  ownership of an externally supplied SDK client.
  """

  use GenServer

  alias BACnet.Stack.SegmentsStore

  @doc false
  @spec start_link(1..60_000) :: GenServer.on_start()
  def start_link(timeout) when is_integer(timeout) and timeout in 1..60_000,
    do: GenServer.start_link(__MODULE__, timeout)

  @impl GenServer
  def init(timeout),
    do: SegmentsStore.init(%{max_segments: 32, apdu_retries: 0, apdu_timeout: timeout})

  @impl GenServer
  def handle_call(message, from, state) do
    # The pinned SDK's overflow branch omits the cancellation flag Client expects.
    case SegmentsStore.handle_call(message, from, state) do
      {:reply, {:error, reason}, next} -> {:reply, {:error, reason, true}, next}
      result -> result
    end
  end

  @impl GenServer
  def handle_cast(message, state), do: SegmentsStore.handle_cast(message, state)

  @impl GenServer
  def handle_info(message, state), do: SegmentsStore.handle_info(message, state)
end
