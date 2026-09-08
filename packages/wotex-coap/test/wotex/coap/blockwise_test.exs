defmodule Wotex.CoAP.BlockwiseTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.CoAP
  alias Wotex.CoAP.{Block, Blockwise, Codec, Connection, Message}

  test "real UDP upload negotiates smaller blocks, preserves identity and returns a complete body" do
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

  property "whole-body reads reassemble exact bytes under every supported negotiated size" do
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

  test "changed representation, invalid continuity and body/exchange budgets fail closed" do
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

  test "uploads require matching atomic continuation acknowledgments and never restart" do
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
    never = fn _, _ -> flunk("must not perform I/O") end

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
