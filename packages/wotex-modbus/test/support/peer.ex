defmodule Wotex.Modbus.TestPeer do
  @moduledoc false

  @doc false
  @spec start(function()) :: {Task.t(), :inet.port_number()}
  def start(handler) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 2000)
        :gen_tcp.close(listener)

        try do
          loop(socket, handler)
        after
          :gen_tcp.close(socket)
        end
      end)

    {task, port}
  end

  defp loop(socket, handler) do
    case :gen_tcp.recv(socket, 6, 2000) do
      {:ok, <<tid::16, 0::16, length::16>>} ->
        {:ok, <<unit, payload::binary>>} = :gen_tcp.recv(socket, length, 2000)

        case handler.(tid, unit, payload) do
          :close ->
            :ok

          {:raw, bytes} ->
            :gen_tcp.send(socket, bytes)
            loop(socket, handler)

          {:split, bytes} ->
            for <<byte <- bytes>>, do: :gen_tcp.send(socket, <<byte>>)
            loop(socket, handler)

          pdu when is_binary(pdu) ->
            :gen_tcp.send(socket, <<tid::16, 0::16, byte_size(pdu) + 1::16, unit, pdu::binary>>)
            loop(socket, handler)
        end

      {:error, :closed} ->
        :ok
    end
  end
end
