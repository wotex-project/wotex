defmodule WotexLabWorkbench.Test.ScriptedModbusPeer do
  @moduledoc false

  # A bounded TCP fault fixture, separate from the independent PyModbus
  # acceptance peer. It can commit a register write and deliberately lose its
  # acknowledgement so ordinary unit tests can exercise uncertain effects.

  @doc false
  @spec start(keyword()) :: map()
  def start(opts \\ []) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {host, port}} = :inet.sockname(listener)
    owner = self()

    lose_ack? = Keyword.get(opts, :lose_ack, true)
    ExUnit.Callbacks.start_supervised!({Task, fn -> serve(listener, owner, 21.0, lose_ack?) end})
    ExUnit.Callbacks.on_exit(fn -> :gen_tcp.close(listener) end)
    %{host: host, port: port}
  end

  defp serve(listener, owner, target, lose_ack?) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        target = exchange(socket, owner, target, lose_ack?)
        :gen_tcp.close(socket)
        serve(listener, owner, target, lose_ack?)

      {:error, _} ->
        :ok
    end
  end

  defp exchange(socket, owner, target, lose_ack?) do
    with {:ok, <<transaction::binary-size(2), 0::16, length::16>>} <-
           :gen_tcp.recv(socket, 6, 1_000),
         true <- length in 2..64,
         {:ok, body} <- :gen_tcp.recv(socket, length, 1_000) do
      send(owner, {:scripted_modbus, body})
      respond(socket, transaction, body, target, lose_ack?)
    else
      _ -> target
    end
  end

  defp respond(socket, transaction, <<unit, 4, 0::16, 2::16>>, target, _) do
    reply(socket, transaction, <<unit, 4, 4, 21.5::float-big-32>>)
    target
  end

  defp respond(socket, transaction, <<unit, 4, 2::16, 2::16>>, target, _) do
    reply(socket, transaction, <<unit, 4, 4, 420.0::float-big-32>>)
    target
  end

  defp respond(socket, transaction, <<unit, 3, 0::16, 2::16>>, target, _) do
    reply(socket, transaction, <<unit, 3, 4, target::float-big-32>>)
    target
  end

  defp respond(
         socket,
         transaction,
         <<unit, 16, 0::16, 2::16, 4, target::float-big-32>>,
         _,
         lose_ack?
       ) do
    unless lose_ack?, do: reply(socket, transaction, <<unit, 16, 0::16, 2::16>>)
    target
  end

  defp respond(_, _, _, target, _), do: target

  defp reply(socket, transaction, body),
    do: :gen_tcp.send(socket, <<transaction::binary, 0::16, byte_size(body)::16, body::binary>>)
end
