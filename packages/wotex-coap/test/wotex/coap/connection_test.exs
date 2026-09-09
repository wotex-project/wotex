defmodule Wotex.CoAP.ConnectionTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Connection, Message}

  test "separate CON response follows empty ACK, ignores wrong token and is acknowledged" do
    {peer, port} =
      peer(fn socket ->
        {:ok, {host, port, bytes}} = :gen_udp.recv(socket, 0, 1000)
        {:ok, request} = Codec.decode(bytes)
        reply(socket, host, port, %Message{type: :ack, code: 0, message_id: request.message_id})

        reply(socket, host, port, %Message{
          type: :non,
          code: 69,
          message_id: 123,
          token: "wrong",
          payload: "bad"
        })

        reply(socket, host, port, %Message{
          type: :con,
          code: 69,
          message_id: 124,
          token: request.token,
          payload: "42"
        })

        {:ok, {_, _, ack}} = :gen_udp.recv(socket, 0, 1000)
        assert {:ok, %{type: :ack, code: 0, message_id: 124}} = Codec.decode(ack)
      end)

    {:ok, conn} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 500, ack_timeout: 20)
    assert {:ok, %{payload: "42"}} = CoAP.send(conn, %{method: :get, path: "/reading"})
    CoAP.disconnect(conn)
    CoAP.disconnect(conn)
    Task.await(peer)
  end

  test "retransmission keeps original bytes and a wrong MID cannot acknowledge it" do
    {peer, port} =
      peer(fn socket ->
        {:ok, {host, port, bytes}} = :gen_udp.recv(socket, 0, 1000)
        {:ok, request} = Codec.decode(bytes)

        reply(socket, host, port, %Message{
          type: :ack,
          code: 69,
          message_id: rem(request.message_id + 1, 65_536),
          token: request.token
        })

        {:ok, {^host, ^port, ^bytes}} = :gen_udp.recv(socket, 0, 1000)
        reply(socket, host, port, %{request | type: :ack, code: 69, payload: "done"})
      end)

    {:ok, conn} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 500, ack_timeout: 10)
    assert {:ok, %{payload: "done"}} = CoAP.send(conn, %{method: :get, path: "/"})
    CoAP.disconnect(conn)
    Task.await(peer)
  end

  test "timeout and reset are explicit and owner death closes the session" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    {:ok, conn} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 20, ack_timeout: 5)

    assert {:error, %{code: :timeout, effect: :unknown}} =
             CoAP.send(conn, %{method: :put, path: "/", payload: "x", confirmable: false})

    :gen_udp.close(socket)
    CoAP.disconnect(conn)
    assert {:error, _} = CoAP.send(conn, %{method: :get, path: "/"})

    {peer, port} =
      peer(fn socket ->
        {:ok, {host, port, bytes}} = :gen_udp.recv(socket, 0, 1000)
        {:ok, request} = Codec.decode(bytes)
        reply(socket, host, port, %Message{type: :rst, code: 0, message_id: request.message_id})
      end)

    {:ok, conn} = CoAP.connect(host: "127.0.0.1", port: port)
    assert {:error, %{code: :reset}} = CoAP.send(conn, %{method: :get, path: "/"})
    CoAP.disconnect(conn)
    Task.await(peer)
    parent = self()

    owner =
      Task.async(fn ->
        {:ok, conn} = CoAP.connect(host: "127.0.0.1", port: port)
        send(parent, {:conn, conn})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:conn, conn}
    ref = Process.monitor(conn.pid)
    send(owner.pid, :finish)
    Task.await(owner)
    assert_receive {:DOWN, ^ref, :process, _, :normal}
  end

  test "configuration, request validation and compatibility capabilities" do
    for opts <- [
          nil,
          [:bad],
          [host: "bad"],
          [host: "127.0.0.1", security: :tls],
          [host: nil],
          [host: {999, 0, 0, 1}],
          [host: "127.0.0.1", scheme: :coaps],
          [host: "127.0.0.1", port: 0],
          [host: "127.0.0.1", timeout: 0],
          [host: "127.0.0.1", ack_timeout: 0]
        ],
        do: assert(match?({:error, _}, Connection.config(opts)))

    for request <- [
          nil,
          %{},
          %{method: :patch, path: "/"},
          %{method: :get, path: "coap://host/"},
          %{method: :put, path: "/", payload: %{}},
          %{method: :get, path: "/", content_format: :wrong}
        ],
        do: assert(match?({:error, _}, CoAP.message(request)))

    for format <- [:text, :json, :cbor, 256],
        do:
          assert(
            match?(
              {:ok, _},
              CoAP.message(%{
                method: :post,
                path: "/a//b?x=1&x=2",
                payload: "data",
                content_format: format
              })
            )
          )

    assert {:error, _} = Connection.request(nil, nil, 0)
    assert {:error, _} = CoAP.receive(nil, 1)
    assert {:error, _} = CoAP.subscribe(nil, "/")
    assert {:error, _} = CoAP.unsubscribe(nil, "/")
    assert CoAP.capabilities().max_payload_size == 1152
  end

  test "Runtime decodes a real UDP exchange and health checks classify response status" do
    {peer, port} =
      peer(fn socket ->
        for code <- [69, 69, 132] do
          {:ok, {host, port, bytes}} = :gen_udp.recv(socket, 0, 1000)
          {:ok, request} = Codec.decode(bytes)

          reply(socket, host, port, %{
            request
            | type: :ack,
              code: code,
              payload: "42",
              options: [{12, <<50>>}]
          })
        end
      end)

    href = "coap://127.0.0.1:#{port}/value"
    {:ok, form} = Wotex.Form.new(%{"href" => href, "contentType" => "application/json"})
    {:ok, context} = Wotex.Runtime.Context.new(request_id: "loopback")
    execution = Wotex.Runtime.ExecutionContext.new(context, nil)

    request = %Wotex.Runtime.Request{
      operation: :readproperty,
      affordance_type: :property,
      affordance_name: "value",
      form: form,
      resolved_href: href,
      profile: CoAP.profile(),
      request_id: "loopback",
      deadline: nil,
      input: nil
    }

    assert {:ok, %{payload: 42}} =
             Wotex.CoAP.Transport.request(request, execution, ack_timeout: 10)

    {:ok, conn} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 100)
    assert {:ok, :healthy} = CoAP.health_check(conn)
    assert {:error, _} = CoAP.health_check(conn)
    CoAP.disconnect(conn)
    assert {:error, _} = CoAP.health_check(conn)
    Task.await(peer)

    for config <- [
          [:invalid],
          [unknown: true],
          [timeout: 100, timeout: 200],
          [ack_timeout: 0],
          [ack_timeout: 3001]
        ] do
      assert {:error, %Wotex.CoAP.Error{}} =
               Wotex.CoAP.Transport.request(request, execution, config)
    end
  end

  defp peer(fun) do
    parent = self()

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
        {:ok, {_, port}} = :inet.sockname(socket)
        send(parent, {:peer_port, port})

        try do
          fun.(socket)
        after
          :gen_udp.close(socket)
        end
      end)

    receive do
      {:peer_port, port} -> {task, port}
    end
  end

  defp reply(socket, host, port, message) do
    {:ok, bytes} = Codec.encode(message)
    :ok = :gen_udp.send(socket, host, port, bytes)
  end
end
