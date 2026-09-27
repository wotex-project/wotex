defmodule Wotex.Zigbee.TestSerialPeer do
  @moduledoc false

  @behaviour Wotex.Zigbee.SerialPort

  import Bitwise

  @impl Wotex.Zigbee.SerialPort
  def open("simulated-coordinator", options, owner) do
    test_pid = Keyword.fetch!(options, :test_pid)
    version = Keyword.get(options, :version, {2, 0, 3, 2, 0})
    drop_reply = Keyword.get(options, :drop_reply, false)
    drop_version = Keyword.get(options, :drop_version, false)
    port = spawn_link(fn -> loop(owner, test_pid, version, drop_reply, drop_version) end)
    send(test_pid, {:serial_open, port, options})
    {:ok, port}
  end

  def open(_, _, _), do: {:error, :identity_mismatch}

  @impl Wotex.Zigbee.SerialPort
  def write(port, bytes) do
    send(port, {:write, bytes})
    :ok
  end

  @impl Wotex.Zigbee.SerialPort
  def close(port) do
    send(port, :close)
    :ok
  end

  defp loop(owner, test_pid, version, drop_reply, drop_version) do
    receive do
      {:write, bytes} ->
        send(test_pid, {:serial_write, bytes})

        respond(owner,
          port: self(),
          bytes: bytes,
          version: version,
          drop_reply: drop_reply,
          drop_version: drop_version
        )

        loop(owner, test_pid, version, drop_reply, drop_version)

      {:inject, bytes} ->
        send(owner, {:zigbee_serial, self(), bytes})
        loop(owner, test_pid, version, drop_reply, drop_version)

      {:disconnect, reason} ->
        send(owner, {:zigbee_serial_down, self(), reason})

      :close ->
        :ok
    end
  end

  defp respond(owner,
         port: port,
         bytes: <<0xFE, length, cmd0, id, rest::binary>>,
         version: version,
         drop_reply: drop_reply,
         drop_version: drop_version
       ) do
    <<payload::binary-size(^length), _>> = rest

    cond do
      cmd0 == 0x21 and id == 2 and drop_version ->
        :ok

      cmd0 == 0x21 and id == 2 ->
        data =
          version
          |> Tuple.to_list()
          |> :erlang.list_to_binary()

        version_reply = manual_frame(0x61, 2, data)
        <<first, tail::binary>> = version_reply
        send(owner, {:zigbee_serial, port, <<first>>})
        send(owner, {:zigbee_serial, port, tail})

      drop_reply ->
        :ok

      true ->
        send(owner, {:zigbee_serial, port, manual_frame(0x60 ||| (cmd0 &&& 0x1F), id, <<0>>)})

        if cmd0 == 0x24 and id == 1 do
          <<_::little-16, _, source, _::little-16, transaction, _, _, _, _::binary>> = payload

          send(owner, {:zigbee_serial, port, manual_frame(0x44, 0x80, <<0, source, transaction>>)})
        end
    end
  end

  defp manual_frame(cmd0, id, payload) do
    body = <<byte_size(payload), cmd0, id, payload::binary>>

    fcs =
      body
      |> :binary.bin_to_list()
      |> Enum.reduce(0, &bxor/2)

    <<0xFE, body::binary, fcs>>
  end
end
