defmodule Wotex.CoAP.DiscoveryTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Error}

  test "WCO-S04 WCO-D03 WCO-V11 discovery validates route, query, status and media before parsing" do
    for {code, options, payload, result} <- [
          {69, [{12, <<40>>}], "", {:ok, []}},
          {69, [{12, <<0, 40>>}], "</x>;obs", {:ok, [%{href: "/x", attributes: [{"obs", true}]}]}},
          {69, [], "</x>", :unexpected_content_format},
          {69, [{12, <<50>>}], "[]", :unexpected_content_format},
          {68, [{12, <<40>>}], "</x>", :invalid_discovery_response},
          {132, [], "not found", :remote_response},
          {69, [{12, <<40>>}], "unfinished", :invalid_link_format}
        ] do
      {socket, port} = peer()
      {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 500)

      task =
        Task.async(fn -> CoAP.discover(session, %{query: "rt=temperature%2Dc&x=a+b&empty="}) end)

      {endpoint, request} = wire(socket)
      assert request.code == 1 and request.payload == <<>>
      assert Codec.option(request, 11) == [".well-known", "core"]
      assert Codec.option(request, 15) == ["rt=temperature-c", "x=a+b", "empty="]
      assert Codec.option(request, 17) == [<<40>>]

      reply(socket, endpoint, %{
        request
        | type: :ack,
          code: code,
          options: options,
          payload: payload
      })

      actual = Task.await(task)

      if is_atom(result),
        do: assert({:error, %Error{code: ^result}} = actual),
        else: assert(actual == result)

      assert :ok = CoAP.disconnect(session)
      :gen_udp.close(socket)
    end
  end

  test "WCO-C02 WCO-D03 discovery input failures emit no datagram" do
    {socket, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)

    for input <- [
          nil,
          %URI{},
          %{extra: true},
          %{query: "", extra: nil},
          %{query: false},
          %{query: "?rt=x"},
          %{query: String.duplicate("a", 1025)},
          %{query: "x=%xx"},
          %{query: "x=\n"},
          %{query: "x=#fragment"},
          %{query: <<255>>}
        ] do
      assert {:error, %Error{}} = CoAP.discover(session, input)
    end

    assert {:error, %Error{code: :invalid_session}} = CoAP.discover(nil, %{})
    assert {:error, :timeout} = :gen_udp.recv(socket, 0, 20)
    assert :ok = CoAP.disconnect(session)
    :gen_udp.close(socket)
  end

  test "WCO-D02 WCO-D03 absent, empty and exact-limit discovery queries remain distinct" do
    segments = Enum.reverse(["" | List.duplicate(String.duplicate("x", 255), 4)])
    query_at_limit = Enum.join(segments, "&")
    assert byte_size(query_at_limit) == 1024

    for {query, expected} <- [
          {nil, []},
          {"", [""]},
          {query_at_limit, segments}
        ] do
      {socket, port} = peer()
      {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 500)
      task = Task.async(fn -> CoAP.discover(session, %{query: query}) end)
      {endpoint, request} = wire(socket)
      assert request.code == 1
      assert Codec.option(request, 11) == [".well-known", "core"]
      assert Codec.option(request, 15) == expected
      assert Codec.option(request, 17) == [<<40>>]

      reply(socket, endpoint, %{
        request
        | type: :ack,
          code: 69,
          options: [{12, <<40>>}],
          payload: ""
      })

      assert {:ok, []} = Task.await(task)

      assert {:error, %Error{code: :invalid_discovery_request}} =
               CoAP.discover(session, %{query: query_at_limit <> "x"})

      assert {:error, :timeout} = :gen_udp.recv(socket, 0, 20)
      assert :ok = CoAP.disconnect(session)
      :gen_udp.close(socket)
    end
  end

  test "WCO-S02 WCO-D03 complete discovery body uses 64 KiB as a transfer ceiling" do
    for oversized <- [false, true] do
      {socket, port} = peer()
      {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 500)
      task = Task.async(fn -> CoAP.discover(session, %{}) end)
      {endpoint, request} = wire(socket)
      prefix = "</x>;title=\"" <> String.duplicate("a", 4)
      size = if oversized, do: [{28, Codec.uint(65_537)}], else: []

      reply(socket, endpoint, %{
        request
        | type: :ack,
          code: 69,
          options: [{12, <<40>>}, {23, <<8>>}] ++ size,
          payload: prefix
      })

      if oversized do
        assert {:error, %Error{code: :body_limit}} = Task.await(task)
        assert {:error, :timeout} = :gen_udp.recv(socket, 0, 20)
      else
        {endpoint, continuation} = wire(socket)
        assert Codec.option(continuation, 23) == [<<16>>]
        assert Codec.option(continuation, 17) == [<<40>>]

        reply(socket, endpoint, %{
          continuation
          | type: :ack,
            code: 69,
            options: [{12, <<40>>}, {23, <<16>>}],
            payload: "\";obs"
        })

        assert {:ok, [%{href: "/x", attributes: [{"title", "aaaa"}, {"obs", true}]}]} =
                 Task.await(task)
      end

      assert :ok = CoAP.disconnect(session)
      :gen_udp.close(socket)
    end
  end

  test "WCO-D03 WCO-V11 no response is an error and absolute advertised links start no connection" do
    {socket, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 40)
    task = Task.async(fn -> CoAP.discover(session, %{query: nil}) end)
    wire(socket)
    assert {:error, %Error{code: :timeout}} = Task.await(task)
    assert :ok = CoAP.disconnect(session)
    :gen_udp.close(socket)

    {socket, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    task = Task.async(fn -> CoAP.discover(session, %{}) end)
    {endpoint, request} = wire(socket)
    target = "https://unresolved.invalid:1/private"

    reply(socket, endpoint, %{
      request
      | type: :ack,
        code: 69,
        options: [{12, <<40>>}],
        payload: "<" <> target <> ">;anchor=\"/x\";rel=describedby"
    })

    assert {:ok, [%{href: ^target}]} = Task.await(task)
    assert {:error, :timeout} = :gen_udp.recv(socket, 0, 20)
    assert :ok = CoAP.disconnect(session)
    :gen_udp.close(socket)
  end

  test "WCO-D03 WCO-V11 the wire transfer accepts 65536 bytes and refuses the next byte" do
    segment = "</>;x=" <> String.duplicate("a", 1024)
    prefix = Enum.join(List.duplicate(segment, 63), ",") <> ",</>;x="
    body = prefix <> String.duplicate("b", 65_536 - byte_size(prefix))

    for extra <- ["", "b"] do
      {socket, port} = peer()
      {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 5000)
      task = Task.async(fn -> CoAP.discover(session, %{}) end)
      complete = body <> extra
      count = div(byte_size(complete) + 511, 512)

      for number <- 0..(count - 1) do
        {endpoint, request} = wire(socket)
        assert Codec.option(request, 17) == [<<40>>]
        offset = number * 512
        block = binary_part(complete, offset, min(512, byte_size(complete) - offset))
        more = if number + 1 < count, do: 8, else: 0

        reply(socket, endpoint, %{
          request
          | type: :ack,
            code: 69,
            options: [{12, <<40>>}, {23, Codec.uint(number * 16 + more + 5)}],
            payload: block
        })
      end

      if extra == "" do
        assert {:ok, links} = Task.await(task)
        assert length(links) == 64
      else
        assert {:error, %Error{code: :body_limit}} = Task.await(task)
      end

      assert {:error, :timeout} = :gen_udp.recv(socket, 0, 20)
      assert :ok = CoAP.disconnect(session)
      :gen_udp.close(socket)
    end
  end

  test "WCO-D03 WCO-V11 parsing waits for complete Block2 UTF-8 and rejects a malformed suffix" do
    body =
      ~s|</x>;title="aaaé,\\\"tail";TITLE="ignored";anchor="../a%252Fb?x=a,b#here";| <>
        ~s|rel="alternate urn:example:link";hreflang=sv;hreflang=en;x=1;x=2;obs|

    expected = [
      %{
        href: "/x",
        attributes: [
          {"title", "aaaé,\"tail"},
          {"anchor", "../a%252Fb?x=a,b#here"},
          {"rel", "alternate urn:example:link"},
          {"hreflang", "sv"},
          {"hreflang", "en"},
          {"x", "1"},
          {"x", "2"},
          {"obs", true}
        ]
      }
    ]

    refute String.valid?(binary_part(body, 0, 16))

    for {complete, result} <- [
          {body, {:ok, expected}},
          {body <> ",</bad>;title=unquoted", :invalid_link_format},
          {body <> ",</bad>;rt=a;RT=b", :invalid_link_format},
          {body <> ",</bad>;x=\"\n\"", :invalid_link_format},
          {body <> ",</bad>;x=\"" <> <<195>> <> "\"", :invalid_link_format},
          {body <> ",</bad>" <> String.duplicate(";title=\"a\"", 33), :link_limit}
        ] do
      {socket, port} = peer()
      {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000)
      query = "x=%252F&x=+&&empty="
      task = Task.async(fn -> CoAP.discover(session, %{query: query}) end)
      count = div(byte_size(complete) + 15, 16)

      for number <- 0..(count - 1) do
        {endpoint, request} = wire(socket)
        assert request.code == 1 and request.payload == <<>>
        assert Codec.option(request, 11) == [".well-known", "core"]
        assert Codec.option(request, 15) == ["x=%2F", "x=+", "", "empty="]
        assert Codec.option(request, 17) == [<<40>>]
        assert Codec.option(request, 6) == []

        if number > 0,
          do: assert(Codec.option(request, 23) == [Codec.uint(number * 16)])

        assert Task.yield(task, 0) == nil
        offset = number * 16
        more = if number + 1 < count, do: 8, else: 0

        reply(socket, endpoint, %{
          request
          | type: :ack,
            code: 69,
            options: [{4, "links"}, {12, <<40>>}, {23, Codec.uint(number * 16 + more)}],
            payload: binary_part(complete, offset, min(16, byte_size(complete) - offset))
        })
      end

      actual = Task.await(task)

      if is_atom(result),
        do: assert({:error, %Error{code: ^result}} = actual),
        else: assert(actual == result)

      assert :ok = CoAP.disconnect(session)
      assert {:error, :timeout} = :gen_udp.recv(socket, 0, 20)
      :gen_udp.close(socket)
    end
  end

  test "WCO-D04 WCO-V11 discover, read, observe, mutate and cancel share the native contract" do
    {socket, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000)
    task = Task.async(fn -> CoAP.discover(session, %{query: "rt=temperature-c"}) end)
    {endpoint, request} = wire(socket)
    assert Codec.option(request, 15) == ["rt=temperature-c"]

    reply(socket, endpoint, %{
      request
      | type: :ack,
        code: 69,
        options: [{12, <<40>>}],
        payload: "</temperature>;rt=temperature-c;obs"
    })

    assert {:ok, [%{href: "/temperature", attributes: attributes}]} = Task.await(task)
    assert {"obs", true} in attributes
    task = Task.async(fn -> CoAP.get(session, "/temperature", accept: 0) end)
    {endpoint, request} = wire(socket)
    assert Codec.option(request, 17) == [<<>>]
    reply(socket, endpoint, %{request | type: :ack, code: 69, options: [{12, <<>>}], payload: "20"})
    assert {:ok, %{payload: "20"}} = Task.await(task)

    receiver = self()

    task =
      Task.async(fn ->
        CoAP.subscribe(session, %{
          path: "/temperature",
          receiver: receiver,
          renew: false,
          max_queue_length: 1000
        })
      end)

    {endpoint, registration} = wire(socket)
    assert Codec.option(registration, 6) == [<<>>]

    reply(socket, endpoint, %{
      registration
      | type: :ack,
        code: 69,
        options: [{6, <<10>>}, {12, <<>>}],
        payload: "20"
    })

    assert {:ok, handle} = Task.await(task)
    reference = handle.reference

    assert_receive {:wotex_coap, ^reference,
                    {:ok, %{payload: "20"}, %{observe: 10, content_format: 0}}}

    {:ok, writer} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000)

    sockets =
      Enum.map([session, writer], fn value ->
        state = :sys.get_state(value.pid)
        :sys.get_state(state.handle.pid).socket
      end)

    for serial <- [11, 12] do
      task = Task.async(fn -> CoAP.put(writer, "/temperature", "21", content_format: 0) end)
      {writer_endpoint, request} = wire(socket)
      assert writer_endpoint != endpoint
      assert request.code == 3 and request.payload == "21"
      reply(socket, writer_endpoint, %{request | type: :ack, code: 68, options: [], payload: ""})
      assert {:ok, %{code: 68}} = Task.await(task)

      notification = %{
        registration
        | type: :con,
          code: 69,
          message_id: 700 + serial,
          options: [{6, Codec.uint(serial)}, {12, <<>>}],
          payload: "21"
      }

      reply(socket, endpoint, notification)
      assert {^endpoint, %{type: :ack, code: 0, message_id: mid}} = wire(socket)
      assert mid == 700 + serial
      assert_receive {:wotex_coap, ^reference, {:ok, %{payload: "21"}, %{observe: ^serial}}}
      reply(socket, endpoint, notification)
      assert {^endpoint, %{type: :ack, message_id: ^mid}} = wire(socket)
      refute_received {:wotex_coap, ^reference, _}
    end

    task = Task.async(fn -> CoAP.unsubscribe(session, handle) end)
    {endpoint, cancellation} = wire(socket)
    assert cancellation.token == registration.token
    assert Codec.option(cancellation, 6) == [<<1>>]
    assert Codec.option(cancellation, 11) == ["temperature"]
    reply(socket, endpoint, %{cancellation | type: :ack, code: 69, options: [], payload: ""})
    assert :ok = Task.await(task)
    assert :ok = CoAP.unsubscribe(session, handle)
    assert :ok = CoAP.disconnect(session)
    assert :ok = CoAP.disconnect(writer)
    assert Enum.all?(sockets, &(:erlang.port_info(&1) == :undefined))
    assert {:error, :timeout} = :gen_udp.recv(socket, 0, 20)
    :gen_udp.close(socket)
    refute_received {:wotex_coap, ^reference, _}
  end

  defp peer do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    {socket, port}
  end

  defp wire(socket) do
    assert {:ok, {host, port, bytes}} = :gen_udp.recv(socket, 0, 1000)
    assert {:ok, message} = Codec.decode(bytes)
    {{host, port}, message}
  end

  defp reply(socket, {host, port}, message) do
    {:ok, bytes} = Codec.encode(message)
    :ok = :gen_udp.send(socket, host, port, bytes)
  end
end
