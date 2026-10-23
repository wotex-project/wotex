defmodule WotexLabWorkbench.ModbusThing do
  @moduledoc "One room's bounded Modbus transport actor and actual operation counters."

  @behaviour Wotex.Runtime.Transport

  use GenServer

  alias Wotex.Modbus.{Error, Transport}
  alias Wotex.Runtime.{Request, Result}

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @doc "Starts a room-owned actor without opening a socket or reading a Property."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) == [:owner] do
      owner = Keyword.get(opts, :owner)

      if is_pid(owner) and node(owner) == node() and Process.alive?(owner),
        do: GenServer.start_link(__MODULE__, opts),
        else: {:error, Error.new(:invalid_options)}
    else
      {:error, Error.new(:invalid_options)}
    end
  end

  def start_link(_), do: {:error, Error.new(:invalid_options)}

  @doc "Returns only this actor's actual calls, refusals and retained read receipts."
  @spec stats(pid()) :: map()
  def stats(pid), do: GenServer.call(pid, :stats)

  @doc "Binds the owning room's policy as the additional Action caller, once."
  @spec bind_policy(pid(), pid()) :: :ok | {:error, Error.t()}
  def bind_policy(pid, policy), do: GenServer.call(pid, {:bind_policy, policy})

  @doc "Delegates the owning room's explicit operation to the public Modbus transport."
  @impl Wotex.Runtime.Transport
  @spec request(Request.t(), Wotex.Runtime.ExecutionContext.t(), pid()) :: term()
  def request(request, context, pid) when is_pid(pid) and node(pid) == node() do
    GenServer.call(pid, {:request, request, context}, 2_000)
  catch
    :exit, _ -> {:error, disconnected(request)}
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @impl GenServer
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)

    if is_pid(owner) and node(owner) == node() and Process.alive?(owner) do
      {:ok,
       %{
         owner: owner,
         policy: nil,
         monitor: Process.monitor(owner),
         stats: %{handler_calls: 0, rejected: 0, subscriptions: 0, state: %{}}
       }}
    else
      {:stop, :invalid_owner}
    end
  end

  @impl GenServer
  def handle_call(:stats, _, state), do: {:reply, state.stats, state}

  def handle_call({:bind_policy, policy}, {owner, _}, %{owner: owner, policy: nil} = state)
      when is_pid(policy) and node(policy) == node() do
    if Process.alive?(policy),
      do: {:reply, :ok, %{state | policy: policy}},
      else: {:reply, {:error, Error.new(:invalid_transport_context)}, state}
  end

  def handle_call({:request, request, context}, {owner, _}, %{owner: owner} = state) do
    perform(request, context, state)
  end

  def handle_call(
        {:request, %Request{operation: :invokeaction} = request, context},
        {policy, _},
        %{policy: policy} = state
      ) do
    perform(request, context, state)
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_transport_context)}, state}

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _, _}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  defp disconnected(%Request{operation: operation})
       when operation in [:writeproperty, :invokeaction],
       do: Error.with_effect(Error.new(:disconnected), :unknown)

  defp disconnected(_), do: Error.new(:disconnected)

  defp perform(request, context, state) do
    result =
      if Process.alive?(state.owner),
        do: Transport.request(request, context, timeout: 1_000),
        else: {:error, Error.new(:disconnected)}

    stats = %{state.stats | handler_calls: state.stats.handler_calls + 1}

    stats =
      case result do
        {:ok, %Result{payload: value}} when request.operation == :readproperty ->
          %{stats | state: Map.put(stats.state, request.affordance_name, value)}

        {:error, _} ->
          %{stats | rejected: stats.rejected + 1}

        _ ->
          stats
      end

    {:reply, result, %{state | stats: stats}}
  end
end
