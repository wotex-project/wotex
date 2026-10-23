defmodule WotexLabWorkbench.Test.ScriptedModbusPeer do
  @moduledoc false

  # A bounded TCP fault fixture, separate from the independent PyModbus
  # acceptance peer. It commits a register write and deliberately loses its
  # acknowledgement so ordinary unit tests can exercise uncertain effects.

  @doc false
  @spec start() :: map()
  def start do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {host, port}} = :inet.sockname(listener)
    owner = self()

    ExUnit.Callbacks.start_supervised!({Task, fn -> serve(listener, owner, 21.0) end})
    ExUnit.Callbacks.on_exit(fn -> :gen_tcp.close(listener) end)
    %{host: host, port: port}
  end

  defp serve(listener, owner, target) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        target = exchange(socket, owner, target)
        :gen_tcp.close(socket)
        serve(listener, owner, target)

      {:error, _} ->
        :ok
    end
  end

  defp exchange(socket, owner, target) do
    with {:ok, <<transaction::binary-size(2), 0::16, length::16>>} <-
           :gen_tcp.recv(socket, 6, 1_000),
         true <- length in 2..64,
         {:ok, body} <- :gen_tcp.recv(socket, length, 1_000) do
      send(owner, {:scripted_modbus, body})
      respond(socket, transaction, body, target)
    else
      _ -> target
    end
  end

  defp respond(socket, transaction, <<unit, 4, 0::16, 2::16>>, target) do
    reply(socket, transaction, <<unit, 4, 4, 21.5::float-big-32>>)
    target
  end

  defp respond(socket, transaction, <<unit, 4, 2::16, 2::16>>, target) do
    reply(socket, transaction, <<unit, 4, 4, 420.0::float-big-32>>)
    target
  end

  defp respond(socket, transaction, <<unit, 3, 0::16, 2::16>>, target) do
    reply(socket, transaction, <<unit, 3, 4, target::float-big-32>>)
    target
  end

  defp respond(_, _, <<_, 16, 0::16, 2::16, 4, target::float-big-32>>, _), do: target
  defp respond(_, _, _, target), do: target

  defp reply(socket, transaction, body),
    do: :gen_tcp.send(socket, <<transaction::binary, 0::16, byte_size(body)::16, body::binary>>)
end
