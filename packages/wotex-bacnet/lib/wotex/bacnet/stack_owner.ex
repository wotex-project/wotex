defmodule Wotex.BACnet.StackOwner do
  @moduledoc "Monitored owner for an isolated BACstack process group with zero APDU retries."
  use GenServer
  alias BACnet.Stack.Segmentator
  alias BACnet.Stack.Transport.IPv4Transport
  alias Wotex.BACnet.{Error, SegmentsStore, StackClient}

  @doc "Starts the explicit process group and unwinds partial startup failures."
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts), do: start_link(opts, fn _, start -> start.() end)

  @doc false
  @spec start_link(keyword(), (atom(), (-> term()) -> term())) :: GenServer.on_start()
  def start_link(opts, acquire) do
    case GenServer.start(__MODULE__, {opts, acquire}) do
      {:ok, pid} ->
        Process.link(pid)
        {:ok, pid}

      {:error, _} = error ->
        error
    end
  end

  @doc "Returns the group's owned Client process."
  @spec client(pid()) :: {:ok, pid()} | {:error, Error.t()}
  def client(pid) do
    GenServer.call(pid, :client)
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  @doc "Closes all group resources idempotently."
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.stop(pid, :normal, 1100)
  catch
    :exit, _ -> :ok
  end

  @impl GenServer
  def init({opts, acquire}) do
    Process.flag(:trap_exit, true)
    owner = self()

    steps = [
      {:transport,
       fn _ ->
         IPv4Transport.open(owner, local_ip: opts[:local_ip], bacnet_port: opts[:local_port])
       end},
      {:segmentator,
       fn _ -> Segmentator.start_link(apdu_retries: 0, apdu_timeout: opts[:timeout]) end},
      # BACstack 0.0.1 start_link/1 drops max_segments before init/1.
      {:segments_store,
       fn _ ->
         SegmentsStore.start_link(opts[:timeout])
       end},
      {:client,
       fn group ->
         StackClient.start_link(
           transport: {IPv4Transport, group.transport},
           segmentator: group.segmentator,
           segments_store: group.segments_store,
           apdu_retries: 0,
           apdu_timeout: opts[:timeout]
         )
       end}
    ]

    case start_group(steps, %{}, acquire) do
      {:ok, group} ->
        {:ok,
         group
         |> Map.put(:monitor, Process.monitor(opts[:owner]))
         |> Map.put(:portal, IPv4Transport.get_portal(group.transport))}

      {:error, _} ->
        {:stop, Error.new(:startup_failed)}
    end
  end

  @impl GenServer
  def handle_call(:client, _, state), do: {:reply, {:ok, state.client}, state}

  @impl GenServer
  def handle_info(
        {:bacnet_transport, {_, IPv4Transport}, _, {:apdu, _, _, bytes}, portal} = message,
        %{portal: portal} = state
      )
      when is_binary(bytes) and byte_size(bytes) <= 1476 do
    send(state.client, message)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, _, _}, state), do: {:stop, :normal, state}
  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state), do: cleanup(state)

  defp start_group([], group, _), do: {:ok, group}

  defp start_group([{name, start} | tail], group, acquire) do
    case safe_start(fn group -> acquire.(name, fn -> start.(group) end) end, group) do
      {:ok, pid} ->
        start_group(tail, Map.put(group, name, pid), acquire)

      _ ->
        cleanup(group)
        {:error, :startup_failed}
    end
  end

  defp safe_start(start, group) do
    start.(group)
  rescue
    _ -> {:error, :startup_failed}
  catch
    :exit, _ -> {:error, :startup_failed}
  end

  defp cleanup(group) do
    deadline = System.monotonic_time(:millisecond) + 1000

    for key <- [:client, :segments_store, :segmentator, :transport],
        pid = Map.get(group, key),
        is_pid(pid),
        do: close_child(pid, deadline, key)

    :ok
  end

  defp close_child(pid, deadline, key) do
    started = System.monotonic_time()
    result = stop_child(pid, deadline)

    :telemetry.execute(
      [:wotex, :bacnet, :resource, :stop],
      %{duration: System.monotonic_time() - started},
      %{resource: key, result: result}
    )
  end

  defp stop_child(pid, deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 1)
    GenServer.stop(pid, :normal, timeout)
  catch
    :exit, _ ->
      Process.exit(pid, :kill)
      :forced
  end
end
