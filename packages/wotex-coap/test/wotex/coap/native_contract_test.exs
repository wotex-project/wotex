defmodule Wotex.CoAP.NativeContractTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP
  alias Wotex.CoAP.{Blockwise, Codec, ContractFixture, Error, Message}
  @path Path.expand("../../../docs/specs/fixtures/contract-v1.json", __DIR__)
  @fixture Jason.decode!(File.read!(@path))
  @digest Base.encode16(:crypto.hash(:sha256, File.read!(@path)), case: :lower)
  @operations ~w(codec.encode codec.decode codec.validate message.new observe.fresh)

  for fixture <- @fixture["cases"], fixture["operation"] in @operations do
    @tag fixture_sha256: @digest
    test "WCO-D05 #{fixture["id"]} computes its exact pure result" do
      fixture = unquote(Macro.escape(fixture))
      actual = ContractFixture.run(Map.take(fixture, ["operation", "input"]))
      assert actual == fixture["expectation"]["value"]
    end
  end

  test "WCO-D05 corpus identities are unique with a closed pure, parser and lifecycle operation set" do
    assert @fixture["format"] == "wotex-protocol-contract"
    assert @fixture["version"] == "1.0.0"
    assert @fixture["specification"] == "WCO.11@1.0.0"
    ids = Enum.map(@fixture["cases"], & &1["id"])
    assert length(ids) == 32
    assert MapSet.size(MapSet.new(ids)) == 32
    assert Enum.count(@fixture["cases"], &(&1["operation"] in @operations)) == 22

    assert Enum.all?(
             @fixture["cases"],
             &(&1["operation"] in (@operations ++ ~w(link_format.decode observation.trace)))
           )
  end

  test "WCO-C02 WCO-D02 strict messages reject malformed URI, fields and forged option tails" do
    for path <- [
          "/x%",
          "/x%00%GG",
          "/x%G0",
          "/x%0G",
          "/.",
          "/a/../b",
          "/x#fragment",
          "/x\n",
          "/x y",
          <<255>>,
          String.duplicate("a", 4097)
        ] do
      assert {:error, %Error{code: :invalid_request}} = CoAP.message(%{method: :get, path: path})
    end

    for input <- [
          %{method: :get, path: "/", extra: nil},
          %{method: :get, path: "/", accept: -1},
          %{method: :get, path: "/", accept: :unknown},
          %{method: :post, path: "/", payload: nil},
          %{method: :get, path: "/", confirmable: nil}
        ] do
      assert {:error, %Error{code: :invalid_request}} = CoAP.message(input)
    end

    message = %Message{type: :con, code: 1, message_id: 0}

    for options <- [[{11, "x"} | :invalid], [{11, "x"} | %{tail: nil}], [:bad], nil] do
      assert {:error, %Error{}} = Codec.encode(%{message | options: options})
      assert {:error, %Error{}} = Codec.validate_options(%{message | options: options})
    end

    assert {:ok,
            %{
              options: [
                {11, "a"},
                {11, ""},
                {11, "b"},
                {11, ""},
                {15, ""},
                {15, "x=+"},
                {15, ""},
                {17, <<50>>}
              ]
            }} =
             CoAP.message(%{method: :get, path: "a//b/?&x=+&", accept: :json})

    assert {:ok, %{options: []}} = CoAP.message(%{method: :get, path: ""})
  end

  test "WCO-D01 WCO-D02 all native helpers preserve exact method, body, URI and Accept" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    parent = self()

    peer =
      Task.async(fn ->
        receive do
          :go ->
            for {code, payload} <- [{1, ""}, {2, <<0, 255>>}, {3, ""}, {4, ""}] do
              {:ok, {host, port, bytes}} = :gen_udp.recv(socket, 0, 1000)
              assert {:ok, %{code: ^code, payload: ^payload} = request} = Codec.decode(bytes)
              assert Codec.option(request, 11) == ["a/b"]
              assert Codec.option(request, 15) == ["x=a&b", "x=+"]
              assert Codec.option(request, 17) == [<<>>]

              {:ok, bytes} =
                Codec.encode(%{
                  request
                  | type: :ack,
                    code: 69,
                    options: [{12, <<>>}],
                    payload: "complete"
                })

              :ok = :gen_udp.send(socket, host, port, bytes)
            end

            send(parent, :peer_complete)
        end
      end)

    :ok = :gen_udp.controlling_process(socket, peer.pid)
    send(peer.pid, :go)
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    path = "/a%2Fb?x=a%26b&x=+"

    for {method, arguments} <- [
          get: [path],
          post: [path, <<0, 255>>],
          put: [path, ""],
          delete: [path]
        ] do
      assert {:ok, %Message{payload: "complete", code: 69}} =
               apply(CoAP, method, [session | arguments] ++ [[accept: 0]])
    end

    assert_receive :peer_complete
    assert :ok = CoAP.disconnect(session)
    Task.await(peer)
  end

  test "WCO-C02 WCO-D02 helper options and sessions reject before an exchange" do
    session = %{pid: self(), timeout: 50}

    for options <- [[accept: 0, accept: 0], [unknown: 0], [{:accept, 0} | nil], nil],
        do: assert({:error, %Error{code: :invalid_request}} = CoAP.get(session, "/", options))

    for invalid <- [
          nil,
          %{},
          %{pid: :invalid, timeout: 50},
          %{pid: self(), timeout: 0},
          %{pid: self(), timeout: 50, extra: nil}
        ] do
      assert {:error, %Error{code: :invalid_session}} = CoAP.get(invalid, "/")
      assert {:error, %Error{code: :invalid_session}} = CoAP.disconnect(invalid)
    end

    refute_received {:"$gen_call", _, _}
  end

  test "WCO-S01 WCO-D02 complete-body boundary rejects Continue and unknown response classes" do
    {:ok, request} = CoAP.message(%{method: :put, path: "/", payload: ""})

    for {code, expected} <- [
          {95, :incomplete_response},
          {96, :invalid_response},
          {128, :remote_response},
          {159, :remote_response},
          {160, :remote_response},
          {191, :remote_response},
          {192, :invalid_response}
        ] do
      assert {{:error, %Error{code: ^expected, effect: :unknown} = error}, 1} =
               Blockwise.run(request, [], 0, fn wire, count ->
                 {{:ok, %{wire | type: :ack, code: code, options: [], payload: "diagnostic"}},
                  count + 1}
               end)

      assert error.details == if(expected == :remote_response, do: %{code: code}, else: %{})
    end
  end
end
