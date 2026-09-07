defmodule Wotex.Lab.Test.MqttServer do
  @moduledoc false

  # A scripted in-BEAM MQTT 5 peer for the EMQTT client paths that need no
  # container. It answers CONNECT, SUBSCRIBE, UNSUBSCRIBE, PUBLISH and PINGREQ,
  # reports every received Control Packet to the test process, and lets the
  # test push an Application Message, a server DISCONNECT or a closed socket.
  # It is a scripted test peer, not a broker: MQTT session, retained-message
  # and shared-subscription semantics are proven against eclipse-mosquitto.

  import Bitwise

  @type t :: %{
          required(:port) => pos_integer(),
          required(:controller) => pid(),
          required(:listener) => :gen_tcp.socket()
        }

  @spec start(pid(), keyword()) :: t()
  def start(test, opts \\ []) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listener)
    {:ok, controller} = Agent.start_link(fn -> %{test: test, connection: nil} end)
    acceptor = spawn(fn -> accept(listener, controller, opts) end)

    ExUnit.Callbacks.on_exit(fn ->
      Process.exit(acceptor, :kill)
      :gen_tcp.close(listener)
    end)

    %{port: port, controller: controller, listener: listener}
  end

  @spec href(t()) :: String.t()
  def href(server), do: "mqtt://127.0.0.1:#{server.port}"

  @spec publish(t(), String.t(), binary(), keyword()) :: :ok
  def publish(server, topic, payload, opts \\ []) do
    send(connection(server), {:push, publication(topic, payload, opts)})
    :ok
  end

  defp publication(topic, payload, opts) do
    body = <<byte_size(topic)::16, topic::binary, 0>> <> payload
    retain = if Keyword.get(opts, :retain, false), do: 1, else: 0
    <<0x30 ||| retain>> <> variable(byte_size(body)) <> body
  end

  @spec disconnect(t()) :: :ok
  def disconnect(server) do
    send(connection(server), {:push, <<0xE0, 2, 0x8B, 0>>})
    :ok
  end

  @spec close(t()) :: :ok
  def close(server) do
    send(connection(server), :close)
    :ok
  end

  @spec connection(t()) :: pid()
  def connection(server), do: await_connection(server.controller, 200)

  defp await_connection(_controller, 0), do: raise("no MQTT client connected")

  defp await_connection(controller, attempts) do
    case Agent.get(controller, & &1.connection) do
      pid when is_pid(pid) ->
        pid

      nil ->
        Process.sleep(5)
        await_connection(controller, attempts - 1)
    end
  end

  defp accept(listener, controller, opts) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        connection = spawn(fn -> own(socket, controller, opts) end)
        :ok = :gen_tcp.controlling_process(socket, connection)
        send(connection, :owned)
        Agent.update(controller, &Map.put(&1, :connection, connection))
        accept(listener, controller, opts)

      {:error, _reason} ->
        :ok
    end
  end

  defp own(socket, controller, opts) do
    receive do
      :owned -> :ok
    after
      1_000 -> :ok
    end

    :ok = :inet.setopts(socket, active: true)
    loop(socket, controller, opts, "")
  end

  defp loop(socket, controller, opts, buffer) do
    receive do
      {:tcp, ^socket, data} ->
        {packets, rest} = split(buffer <> data, [])
        Enum.each(packets, &handle(&1, socket, controller, opts))
        loop(socket, controller, opts, rest)

      {:tcp_closed, ^socket} ->
        :ok

      {:push, frame} ->
        :gen_tcp.send(socket, frame)
        loop(socket, controller, opts, buffer)

      :close ->
        :gen_tcp.close(socket)
    end
  end

  defp handle({1, _flags, body}, socket, controller, _opts) do
    report(controller, {:mqtt_connect, connect_info(body)})
    :gen_tcp.send(socket, <<0x20, 3, 0, 0, 0>>)
  end

  defp handle({3, flags, body}, socket, controller, _opts) do
    message = publish_info(flags, body)
    report(controller, {:mqtt_publish, message})

    if message.packet_id do
      :gen_tcp.send(socket, <<0x40, 2, message.packet_id::16>>)
    end
  end

  defp handle({8, _flags, body}, socket, controller, opts) do
    {packet_id, filters} = subscribe_info(body)
    report(controller, {:mqtt_subscribe, filters})
    code = if Keyword.get(opts, :deny_subscribe, false), do: 0x87, else: 0x00
    codes = :binary.copy(<<code>>, length(filters))
    frame = <<packet_id::16, 0>> <> codes
    :gen_tcp.send(socket, <<0x90>> <> variable(byte_size(frame)) <> frame)
    retain(socket, Keyword.get(opts, :retained))
  end

  defp handle({10, _flags, body}, socket, controller, _opts) do
    {packet_id, filters} = unsubscribe_info(body)
    report(controller, {:mqtt_unsubscribe, filters})
    frame = <<packet_id::16, 0>> <> :binary.copy(<<0>>, length(filters))
    :gen_tcp.send(socket, <<0xB0>> <> variable(byte_size(frame)) <> frame)
  end

  defp handle({12, _flags, _body}, socket, controller, _opts) do
    report(controller, :mqtt_pingreq)
    :gen_tcp.send(socket, <<0xD0, 0>>)
  end

  defp handle({14, _flags, _body}, socket, controller, _opts) do
    report(controller, :mqtt_disconnect)
    :gen_tcp.close(socket)
  end

  defp handle(_packet, _socket, _controller, _opts), do: :ok

  defp retain(_socket, nil), do: :ok

  defp retain(socket, {topic, payload}),
    do: :gen_tcp.send(socket, publication(topic, payload, retain: true))

  defp report(controller, message), do: send(Agent.get(controller, & &1.test), message)

  defp split(<<header, rest::binary>> = buffer, acc) do
    with {:ok, length, body} <- remaining(rest, 0, 1),
         true <- byte_size(body) >= length do
      <<packet::binary-size(^length), tail::binary>> = body
      split(tail, [{header >>> 4, header &&& 0x0F, packet} | acc])
    else
      _incomplete -> {Enum.reverse(acc), buffer}
    end
  end

  defp split(buffer, acc), do: {Enum.reverse(acc), buffer}

  defp remaining(<<byte, rest::binary>>, acc, multiplier) do
    total = acc + (byte &&& 0x7F) * multiplier

    if (byte &&& 0x80) == 0 do
      {:ok, total, rest}
    else
      remaining(rest, total, multiplier * 128)
    end
  end

  defp remaining(<<>>, _acc, _multiplier), do: :incomplete

  defp variable(length) when length < 128, do: <<length>>

  defp variable(length),
    do: <<(length &&& 0x7F) ||| 0x80>> <> variable(length >>> 7)

  defp connect_info(<<_size::16, "MQTT", _version, flags, _keepalive::16, rest::binary>>) do
    {_properties, rest} = properties(rest)
    {client_id, rest} = string(rest)
    rest = skip_will(flags &&& 0x04, rest)
    {username, rest} = optional(flags &&& 0x80, rest)
    {password, _rest} = optional(flags &&& 0x40, rest)
    %{client_id: client_id, username: username, password: password}
  end

  defp skip_will(0, rest), do: rest

  defp skip_will(_flag, rest) do
    {_properties, rest} = properties(rest)
    {_topic, rest} = string(rest)
    {_payload, rest} = string(rest)
    rest
  end

  defp optional(0, rest), do: {nil, rest}
  defp optional(_flag, rest), do: string(rest)

  defp publish_info(flags, body) do
    qos = flags >>> 1 &&& 0x03
    {topic, rest} = string(body)
    {packet_id, rest} = packet_id(qos, rest)
    {_properties, payload} = properties(rest)
    %{topic: topic, qos: qos, packet_id: packet_id, payload: payload, retain: (flags &&& 1) == 1}
  end

  defp packet_id(0, rest), do: {nil, rest}
  defp packet_id(_qos, <<packet_id::16, rest::binary>>), do: {packet_id, rest}

  defp subscribe_info(<<packet_id::16, rest::binary>>) do
    {_properties, payload} = properties(rest)
    {packet_id, subscribe_filters(payload, [])}
  end

  defp subscribe_filters(<<size::16, filter::binary-size(size), _options, rest::binary>>, acc),
    do: subscribe_filters(rest, [filter | acc])

  defp subscribe_filters(_rest, acc), do: Enum.reverse(acc)

  defp unsubscribe_info(<<packet_id::16, rest::binary>>) do
    {_properties, payload} = properties(rest)
    {packet_id, unsubscribe_filters(payload, [])}
  end

  defp unsubscribe_filters(<<size::16, filter::binary-size(size), rest::binary>>, acc),
    do: unsubscribe_filters(rest, [filter | acc])

  defp unsubscribe_filters(_rest, acc), do: Enum.reverse(acc)

  defp properties(binary) do
    {:ok, size, rest} = remaining(binary, 0, 1)
    <<properties::binary-size(^size), payload::binary>> = rest
    {properties, payload}
  end

  defp string(<<size::16, value::binary-size(size), rest::binary>>), do: {value, rest}
end
