defmodule Wotex.Modbus.SessionTrace do
  @moduledoc false

  import ExUnit.Assertions
  alias Wotex.Modbus
  alias Wotex.Modbus.{Connection, Error}

  @doc false
  @spec run(map(), (non_neg_integer() -> :ok)) :: map()
  def run(input, advance_clock) do
    endpoint = input["endpoint"]

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    peer = Task.async(fn -> observe_wire(listener) end)

    {:ok, session} =
      Modbus.connect(
        host: endpoint["host"],
        port: port,
        unit_id: endpoint["unit_id"],
        transaction_id: input["initial_transaction_id"]
      )

    socket = :sys.get_state(session.pid).socket
    monitor = Process.monitor(session.pid)
    state = %{session: session, peer: peer, calls: %{}, results: %{}}

    final =
      Enum.reduce(input["events"], state, fn event, acc ->
        :ok = advance_clock.(event["at_ms"])
        event(event, acc)
      end)

    wire = Task.await(peer)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
    :ok = :gen_tcp.close(listener)

    actual = %{
      outbound_hex: wire,
      results: final.results,
      owned_resources: %{
        sockets: if(:erlang.port_info(socket) == :undefined, do: 0, else: 1),
        owners: if(Process.alive?(session.pid), do: 1, else: 0),
        pending_calls: Enum.count(final.calls, fn {_, task} -> Process.alive?(task.pid) end)
      }
    }

    :ok = Connection.close(session.pid)

    actual
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp event(%{"event" => "call", "operation" => "write_holding_register"} = event, state) do
    session = %{state.session | timeout: event["deadline_ms"] - event["at_ms"]}

    task =
      Task.async(fn -> Modbus.write_holding_register(session, event["offset"], event["input"]) end)

    %{state | calls: Map.put(state.calls, event["id"], task)}
  end

  defp event(%{"event" => "peer_close"}, state) do
    send(state.peer.pid, {:close_after_request, self()})
    assert_receive :peer_closed, 1000
    state
  end

  defp event(%{"event" => "drain"}, state) do
    results =
      Map.new(state.calls, fn {id, task} ->
        {id, Map.get_lazy(state.results, id, fn -> normalize(Task.await(task)) end)}
      end)

    %{state | results: results}
  end

  defp observe_wire(listener) do
    {:ok, socket} = :gen_tcp.accept(listener, 1000)
    {:ok, <<_::32, length::16>> = header} = :gen_tcp.recv(socket, 6, 1000)
    {:ok, body} = :gen_tcp.recv(socket, length, 1000)

    receive do
      {:close_after_request, caller} ->
        :ok = :gen_tcp.close(socket)
        send(caller, :peer_closed)
        [Base.encode16(header <> body, case: :lower)]
    after
      1000 -> raise "trace did not close its owned peer"
    end
  end

  defp normalize({:error, %Error{} = error}) do
    %{status: :error, error: Map.take(error, [:code, :field, :details, :retryable, :effect])}
  end
end
