defmodule Wotex.CoAP.BlockwiseTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.CoAP
  alias Wotex.CoAP.{Block, Blockwise, Codec, Connection, Message}

  test "WCO-S02 WCO-V03 UDP upload negotiates smaller blocks and preserves its complete body" do
    parent = self()
    body = :binary.copy("a", 1100)

    peer =
      Task.async(fn ->
        {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
        {:ok, {_, port}} = :inet.sockname(socket)
        send(parent, {:port, port})

        try do
          requests =
            for {number, count} <- [{0, 512}, {4, 128}, {5, 128}, {6, 128}, {7, 128}, {8, 76}] do
              {:ok, {host, port, bytes}} = :gen_udp.recv(socket, 0, 1000)
              {:ok, request} = Codec.decode(bytes)
              [encoded] = Codec.option(request, 27)
              assert {:ok, %{number: ^number}} = Block.decode(encoded)
              assert byte_size(request.payload) == count
              more = number != 8

              reply = %{
                response(request, if(more, do: 95, else: 68))
                | options: [{27, block(number, more, 128)}]
              }

              {:ok, bytes} = Codec.encode(reply)
              :ok = :gen_udp.send(socket, host, port, bytes)
              request
            end

          assert IO.iodata_to_binary(Enum.map(requests, & &1.payload)) == body
          assert MapSet.size(MapSet.new(requests, & &1.token)) == 1
          assert MapSet.size(MapSet.new(requests, & &1.message_id)) == 6
          [tag] = Codec.option(hd(requests), 292)
          assert byte_size(tag) == 8
          assert Enum.all?(requests, &(Codec.option(&1, 292) == [tag]))
        after
          :gen_udp.close(socket)
        end
      end)

    assert_receive {:port, port}
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 2000)

    try do
      assert {:ok, %{code: 68, options: []}} =
               CoAP.send(session, %{method: :put, path: "/body", payload: body})
    after
      CoAP.disconnect(session)
    end

    Task.await(peer)
  end

  property "WCO-S02 WCO-V04 whole-body reads reassemble every supported negotiated size" do
    check all(
            body <- binary(min_length: 1, max_length: 2048),
            size <- member_of([16, 32, 64, 128, 256, 512, 1024])
          ) do
      exchange = fn request, count ->
        [value] = Codec.option(request, 23)
        {:ok, current} = Block.decode(value)
        offset = current.number * current.size
        length = min(size, byte_size(body) - offset)

        reply = %{
          response(request, 69)
          | payload: binary_part(body, offset, length),
            options: [
              {23, block(div(offset, size), offset + length < byte_size(body), size)},
              {4, "tag"},
              {12, <<42>>},
              {28, Codec.uint(byte_size(body))}
            ]
        }

        {{:ok, reply}, count + 1}
      end

      assert {{:ok, %{payload: ^body} = reply}, count} =
               Blockwise.run(request(), [block_size: size], 0, exchange)

      assert count == div(byte_size(body) + size - 1, size)
      assert Codec.option(reply, 23) == []
      assert Codec.option(reply, 4) == ["tag"]
    end
  end

  test "WCO-S02 WCO-V04 changed identity, continuity and body/exchange budgets fail closed" do
    first = %{
      response(request(), 69)
      | payload: :binary.copy("a", 16),
        options: [{23, block(0, true, 16)}, {4, "one"}, {12, <<42>>}]
    }

    last = %{first | payload: "end", options: [{23, block(1, false, 16)}, {4, "one"}, {12, <<42>>}]}

    for {second, code} <- [
          {%{last | options: []}, :missing_block},
          {%{last | options: [{23, block(1, false, 32)}]}, :block_size_changed},
          {%{last | options: [{23, block(1, false, 16)}, {4, "two"}, {12, <<42>>}]},
           :representation_changed},
          {%{last | code: 132}, :remote_response},
          {%{last | options: [{23, block(0, false, 16)}, {4, "one"}, {12, <<42>>}]},
           :block_out_of_order},
          {%{last | options: [{23, <<7>>}]}, :invalid_block_size}
        ] do
      assert {{:error, %{code: ^code}}, 2} = replies([first, second])
    end

    assert {{:error, %{code: :body_limit}}, 1} = replies([first], max_body_size: 15)
    assert {{:error, %{code: :block_limit}}, 1} = replies([first], max_blocks: 1)
    assert {{:error, %{code: :body_limit}}, 2} = replies([first, last], max_body_size: 18)
    assert {{:error, %{code: :invalid_block_payload}}, 1} = replies([%{first | payload: "short"}])

    assert {{:error, %{code: :body_limit}}, 1} =
             replies([%{first | options: [{28, <<255>>} | first.options]}], max_body_size: 100)

    assert {{:error, %{code: :invalid_block_size}}, 1} =
             replies([%{first | options: [{23, block(0, false, 1024)}]}])

    assert {{:error, %{code: :body_limit}}, 1} =
             replies([%{last | options: [], payload: "too long"}], max_body_size: 2)

    assert {{:error, %{code: :timeout}}, 1} =
             Blockwise.run(request(), [], 0, fn _, _ -> {{:error, CoAP.Error.new(:timeout)}, 1} end)
  end

  test "WCO-S02 WCO-V03 uploads require atomic matching ACKs and never restart" do
    message = %{request() | code: 3, payload: :binary.copy("x", 33), options: [{5, <<>>}]}
    good = %{response(message, 95) | options: [{27, block(0, true, 16)}]}

    for {reply, code} <- [
          {%{good | code: 141}, :remote_response},
          {%{good | options: []}, :missing_block},
          {%{good | options: [{27, block(1, true, 16)}]}, :block_ack_mismatch},
          {%{good | options: [{27, block(0, true, 32)}]}, :block_ack_mismatch},
          {%{good | options: [{27, block(0, false, 16)}]}, :non_atomic_block_write},
          {%{good | payload: "wrong"}, :non_atomic_block_write},
          {%{good | code: 68}, :non_atomic_block_write}
        ] do
      assert {{:error, %{code: ^code, effect: :unknown}}, 1} =
               Blockwise.run(message, [block_size: 16], 0, fn _, _ -> {{:ok, reply}, 1} end)
    end

    callback = fn request, n ->
      assert Codec.option(request, 5) == if(n == 0, do: [<<>>], else: [])
      reply = %{good | options: [{27, block(n, true, 16)}]}
      {{:ok, reply}, n + 1}
    end

    assert {{:error, %{code: :incomplete_block_write}}, 3} =
             Blockwise.run(message, [block_size: 16], 0, callback)
  end

  test "upload response bodies continue using the original method and request tag" do
    message = %{request() | code: 2, payload: :binary.copy("x", 17)}

    callback = fn wire, n ->
      assert wire.code == 2
      assert Codec.option(wire, 292) == [message.token]

      reply =
        case n do
          0 ->
            %{response(wire, 95) | options: [{27, block(0, true, 16)}]}

          1 ->
            %{
              response(wire, 68)
              | options: [{27, block(1, false, 16)}, {23, block(0, true, 16)}],
                payload: :binary.copy("z", 16)
            }

          2 ->
            assert wire.payload == <<>>
            assert Codec.option(wire, 27) == []
            assert Codec.option(wire, 23) == [block(1, false, 16)]
            %{response(wire, 68) | options: [{23, block(1, false, 16)}], payload: "last"}
        end

      {{:ok, reply}, n + 1}
    end

    assert {{:ok, %{payload: body}}, 3} = Blockwise.run(message, [block_size: 16], 0, callback)
    assert body == :binary.copy("z", 16) <> "last"
  end

  test "invalid settings and forged messages fail before the exchange callback" do
    test = self()

    never = fn _, _ ->
      send(test, :unexpected_callback)
      flunk("must not perform I/O")
    end

    for opts <- [
          nil,
          [:bad],
          [unknown: 1],
          [block_size: 8],
          [max_body_size: 0],
          [max_blocks: 0],
          [block_size: 16, block_size: 32]
        ] do
      assert {:error, _} = Blockwise.config(opts)
    end

    assert {{:error, _}, :untouched} = Blockwise.run(request(), [max_blocks: 0], :untouched, never)

    for invalid <- [
          %{request() | code: 5},
          %{request() | options: [{23, <<>>}]},
          %{request() | options: [{27, <<>>}]},
          %{request() | options: [:invalid]},
          %{request() | payload: nil},
          %{request() | payload: :binary.copy("a", 1_048_577)},
          %{request() | payload: :binary.copy("a", 513)}
        ] do
      assert {{:error, _}, :untouched} = Blockwise.run(invalid, [], :untouched, never)
    end

    assert {:error, _} = Connection.transfer(nil, nil, 0)
    assert {:error, _} = Connection.transfer(self(), request(), 1, max_blocks: 0)
    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, _, _, _}
    assert {:error, _} = Connection.transfer(dead, request(), 1)

    for value <- [
          %{request() | options: [{6, <<0::32>>}]},
          %{request() | options: [{5, <<1>>}]},
          %{request() | options: [{4, <<>>}]},
          nil
        ] do
      assert {:error, _} = Codec.validate_options(value)
    end

    assert :ok = Codec.validate_options(%{request() | options: [{12, <<0, 0>>}]})
    assert {:error, _} = CoAP.message(%{method: :get, path: "/", confirmable: :yes})
    refute_received :unexpected_callback
  end

  property "WCO-S02 WCO-V04 WCO-V10 first-report continuation retains original identity" do
    check all(
            body <- binary(min_length: 1, max_length: 3000),
            size <- member_of([16, 32, 64, 128, 256, 512, 1024])
          ) do
      first = report(body, size)
      message = %{request() | options: [{6, <<>>}, {11, "x"}, {15, "a=b"}]}

      callback = fn wire, count ->
        assert wire.code == 1
        assert wire.token == message.token and wire.token != first.token
        assert wire.payload == <<>>
        assert Codec.option(wire, 6) == []
        assert Codec.option(wire, 11) == ["x"]
        assert Codec.option(wire, 15) == ["a=b"]
        [encoded] = Codec.option(wire, 23)
        {:ok, block} = Block.decode(encoded)
        assert block.number == count and block.more == false and block.size == size
        offset = count * size
        length = min(size, byte_size(body) - offset)

        reply = %{
          response(wire, 69)
          | payload: binary_part(body, offset, length),
            options: [
              {4, "tag"},
              {12, <<>>},
              {23, block(count, offset + length < byte_size(body), size)}
            ]
        }

        {{:ok, reply}, count + 1}
      end

      assert {{:ok, complete}, count} =
               Blockwise.continue(message, first, [block_size: size], 1, callback)

      assert count == div(byte_size(body) + size - 1, size)

      assert complete == %{
               first
               | payload: body,
                 options: Enum.reject(first.options, &(elem(&1, 0) == 23))
             }
    end
  end

  test "WCO-S02 WCO-V04 WCO-V10 continuation rejects invalid first reports before callback" do
    first = report(:binary.copy("x", 17), 16)
    test = self()

    never = fn _, _ ->
      send(test, :unexpected_callback)
      flunk("invalid first report must not perform I/O")
    end

    for invalid <- [
          nil,
          Map.delete(first, :code),
          Map.delete(first, :payload),
          Map.put(first, :extra, true),
          %{first | code: 95},
          %{first | code: 128},
          %{first | options: [{23, <<7>>}]},
          %{first | options: [{23, block(1, true, 16)}]},
          %{first | options: [{23, block(0, true, 16)}, {23, <<>>}]},
          %{first | payload: "short"}
        ] do
      assert {{:error, _}, :untouched} =
               Blockwise.continue(request(), invalid, [], :untouched, never)
    end

    for invalid <- [
          nil,
          Map.delete(request(), :token),
          Map.put(request(), :extra, true),
          %{request() | code: 3},
          %{request() | payload: "body"}
        ] do
      assert {{:error, _}, :untouched} = Blockwise.continue(invalid, first, [], :untouched, never)
    end

    assert {{:error, %{code: :continuation_token_conflict}}, :untouched} =
             Blockwise.continue(%{request() | token: first.token}, first, [], :untouched, never)

    assert {{:error, %{code: :body_limit}}, :untouched} =
             Blockwise.continue(request(), first, [max_body_size: 15], :untouched, never)

    assert {{:error, %{code: :block_limit}}, :untouched} =
             Blockwise.continue(request(), first, [max_blocks: 1], :untouched, never)

    assert {{:error, _}, :untouched} = Blockwise.continue(request(), first, [], :untouched, nil)
    assert {{:error, _}, :untouched} = Blockwise.run(request(), [], :untouched, nil)
    assert {:error, _} = Blockwise.config([{:block_size, 16} | nil])
    refute_received :unexpected_callback
  end

  test "WCO-S02 WCO-V04 first-report continuation never returns an incomplete or changed prefix" do
    first = report(:binary.copy("x", 17), 16)

    last = %{
      first
      | token: request().token,
        payload: "z",
        options: [{4, "tag"}, {12, <<>>}, {23, block(1, false, 16)}]
    }

    for {reply, code} <- [
          {%{last | options: []}, :missing_block},
          {%{last | code: 68}, :representation_changed},
          {%{last | options: [{4, "other"}, {12, <<>>}, {23, block(1, false, 16)}]},
           :representation_changed},
          {%{last | options: [{4, "tag"}, {12, <<42>>}, {23, block(1, false, 16)}]},
           :representation_changed},
          {%{last | options: [{4, "tag"}, {12, <<>>}, {23, block(1, false, 32)}]},
           :block_size_changed},
          {%{last | code: 136}, :remote_response},
          {%{last | code: 141}, :remote_response},
          {%{last | options: [{4, "tag"}, {12, <<>>}, {23, block(2, false, 16)}]},
           :block_out_of_order}
        ] do
      assert {{:error, %{code: ^code}}, 1} =
               Blockwise.continue(request(), first, [], 0, fn _, count ->
                 {{:ok, reply}, count + 1}
               end)
    end

    assert {{:error, %{code: :timeout}}, 1} =
             Blockwise.continue(request(), first, [], 0, fn _, _ ->
               {{:error, CoAP.Error.new(:timeout)}, 1}
             end)

    assert {{:error, %{code: :body_limit}}, 1} =
             Blockwise.continue(request(), first, [max_body_size: 16], 0, fn _, _ ->
               {{:ok, last}, 1}
             end)

    complete = %{first | options: [{6, <<10>>}], payload: "one"}

    assert {{:ok, ^complete}, :untouched} =
             Blockwise.continue(request(), complete, [max_blocks: 1], :untouched, fn _, _ ->
               flunk("complete")
             end)

    assert {{:error, %{code: :body_limit}}, :untouched} =
             Blockwise.continue(request(), complete, [max_body_size: 1], :untouched, fn _, _ ->
               flunk("limit")
             end)
  end

  test "WCO-S02 WCO-V04 Size2 limits apply even to responses without a Block2 descriptor" do
    first = %{report("x", 16) | options: [{28, Codec.uint(100)}]}
    test = self()

    never = fn _, _ ->
      send(test, :unexpected_callback)
      flunk("oversized first response must not acquire another exchange")
    end

    assert {{:error, %{code: :body_limit}}, :untouched} =
             Blockwise.continue(request(), first, [max_body_size: 10], :untouched, never)

    assert {{:error, %{code: :body_limit}}, 1} =
             Blockwise.run(request(), [max_body_size: 10], 0, fn _, _ -> {{:ok, first}, 1} end)

    refute_received :unexpected_callback
  end

  test "WCO-C02 WCO-S02 malformed callback results stay structured and preserve callback state" do
    first = report(:binary.copy("x", 17), 16)

    for callback <- [
          fn _, _ -> :malformed end,
          fn _, _ -> raise "failure" end,
          fn _, _ -> {{:ok, nil}, :after_reply} end,
          fn _, _ -> {{:ok, %{first | payload: :binary.copy("x", 1153)}}, :after_reply} end
        ] do
      assert {{:error, %CoAP.Error{}}, state} =
               Blockwise.continue(request(), first, [], :before_reply, callback)

      assert state in [:before_reply, :after_reply]
    end
  end

  test "WCO-S02 WCO-V04 WCO-V10 UDP continues the received report without fetching block zero" do
    parent = self()
    body = :binary.copy("a", 33)
    first = report(body, 16)

    peer =
      Task.async(fn ->
        {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
        {:ok, {_, port}} = :inet.sockname(socket)
        send(parent, {:port, port})

        try do
          requests =
            for number <- [1, 2] do
              {:ok, {host, port, bytes}} = :gen_udp.recv(socket, 0, 1000)
              {:ok, wire} = Codec.decode(bytes)
              assert wire.code == 1 and wire.payload == <<>>
              assert wire.token != first.token and byte_size(wire.token) == 8
              assert Codec.option(wire, 6) == []
              assert Codec.option(wire, 23) == [block(number, false, 16)]
              assert Codec.option(wire, 11) == ["x"]
              count = if number == 1, do: 16, else: 1

              reply = %{
                response(wire, 69)
                | payload: binary_part(body, number * 16, count),
                  options: [{4, "tag"}, {12, <<>>}, {23, block(number, number == 1, 16)}]
              }

              {:ok, bytes} = Codec.encode(reply)
              :ok = :gen_udp.send(socket, host, port, bytes)
              wire
            end

          assert MapSet.size(MapSet.new(requests, & &1.token)) == 1
          assert MapSet.size(MapSet.new(requests, & &1.message_id)) == 2
          assert {:error, :timeout} = :gen_udp.recv(socket, 0, 20)
        after
          :gen_udp.close(socket)
        end
      end)

    assert_receive {:port, port}
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    {:ok, request} = CoAP.message(%{method: :get, path: "/x"})
    assert {:ok, completed} = Connection.continue(session.pid, request, first, 1000)
    assert completed.payload == body
    assert completed.token == first.token and completed.message_id == first.message_id
    assert Codec.option(completed, 6) == [<<10>>]
    assert Codec.option(completed, 14) == [<<60>>]
    assert :ok = CoAP.disconnect(session)
    Task.await(peer)
    assert CoAP.capabilities().max_datagram_size == 1152
    assert CoAP.capabilities().max_body_size == 1_048_576
    assert CoAP.capabilities().max_payload_size == 1152
  end

  test "WCO-S02 WCO-V04 missing UDP continuation cannot return the first report prefix" do
    parent = self()
    first = report(:binary.copy("a", 17), 16)

    peer =
      Task.async(fn ->
        {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
        {:ok, {_, port}} = :inet.sockname(socket)
        send(parent, {:port, port})
        {:ok, {_, _, bytes}} = :gen_udp.recv(socket, 0, 1000)
        {:ok, request} = Codec.decode(bytes)
        assert Codec.option(request, 23) == [block(1, false, 16)]
        receive do: (:closed -> :gen_udp.close(socket))
      end)

    assert_receive {:port, port}
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)

    assert {:error, %{code: :timeout, effect: :none}} =
             Connection.continue(session.pid, request(), first, 30)

    assert :ok = CoAP.disconnect(session)
    send(peer.pid, :closed)
    Task.await(peer)
  end

  defp report(body, size) do
    %Message{
      type: :con,
      code: 69,
      message_id: 123,
      token: "observed",
      payload: binary_part(body, 0, min(size, byte_size(body))),
      options: [
        {4, "tag"},
        {6, <<10>>},
        {12, <<>>},
        {14, <<60>>},
        {23, block(0, byte_size(body) > size, size)}
      ]
    }
  end

  defp replies(values, opts \\ []) do
    Blockwise.run(request(), opts, 0, fn _, n -> {{:ok, Enum.fetch!(values, n)}, n + 1} end)
  end

  defp request, do: %Message{type: :con, code: 1, message_id: 0, token: "transfer"}
  defp response(message, code), do: %{message | type: :ack, code: code, options: [], payload: <<>>}

  defp block(number, more, size) do
    {:ok, value} = Block.encode(%Block{number: number, more: more, size: size})
    value
  end
end
