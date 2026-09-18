defmodule WotexLabWorkbench.Investigation.Status do
  @moduledoc """
  Retains the latest provider transition for the trusted local Workbench host.

  The explicitly started GenServer uses a fixed host-local name and stores one
  supplied status map. `reset/0` restores the idle value; no history or durable
  record is kept. Callers supply normalized, public fields because `put/1` does
  not redact or validate their contents. This process is not a per-tenant store
  and belongs only to the admitted local investigation profile.
  """

  use GenServer

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Reads the most recently published transition."
  @spec get() :: map()
  def get, do: GenServer.call(__MODULE__, :get)

  @doc "Stores one transition."
  @spec put(map()) :: :ok
  def put(status), do: GenServer.call(__MODULE__, {:put, status})

  @doc "Restores the idle state."
  @spec reset() :: :ok
  def reset, do: put(idle())

  @impl GenServer
  def init(_), do: {:ok, idle()}

  @impl GenServer
  def handle_call(:get, _, state), do: {:reply, state, state}
  def handle_call({:put, status}, _, _), do: {:reply, :ok, status}

  defp idle,
    do: %{state: :idle, provider: nil, model: nil, reason: nil, completed_at: nil}
end
