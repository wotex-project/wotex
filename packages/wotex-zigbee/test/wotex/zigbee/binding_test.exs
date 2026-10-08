defmodule Wotex.Zigbee.BindingTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Binding, Command, Error, Event, Frame}

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @destination <<1, 2, 3, 4, 5, 6, 7, 8>>
  @profile Path.expand("../../support/profiles/zdo-binding-mt-r1.14.json", __DIR__)

  test "reviewed literal MT requests execute without encoder round trips as the oracle" do
    profile = :json.decode(File.read!(@profile))
    assert profile["source"]["revision"] == "1.14"
    before = Process.info(self(), :messages)

    for vector <- profile["adoption"]["requests"] do
      operation = if vector["operation"] == "bind", do: :bind, else: :unbind
      target = if vector["target"] == "group", do: {:group, 0x2345}, else: {:ieee, @destination, 2}
      assert {:ok, request} = Binding.new(options(operation: operation, target: target))
      assert {:ok, frame} = Binding.frame(request)
      assert frame.payload == Base.decode16!(vector["payload_hex"], case: :mixed)
      assert {:ok, bytes} = Frame.encode(frame)
      assert bytes == Base.decode16!(vector["wire_hex"], case: :mixed)
      refute Command.admitted?(frame)
      refute bytes =~ request.correlation_id
    end

    assert Process.info(self(), :messages) == before
  end

  test "complete explicit selectors reject coercion, reserved routes and unsupported address modes" do
    for {key, value} <- [
          operation: :permit_join,
          peer_ieee: <<0::64>>,
          peer_ieee: <<0xFFFFFFFFFFFFFFFF::64>>,
          peer_ieee: "credential-canary",
          route_address: -1,
          route_address: 0xFFF8,
          route_address: 1.0,
          source_endpoint: 0,
          source_endpoint: 241,
          cluster: -1,
          cluster: 65_536,
          correlation_id: <<>>,
          correlation_id: :binary.copy(<<1>>, 65),
          target: {:short, 0x1234, 1},
          target: {:ieee, <<0::64>>, 1},
          target: {:ieee, @destination, 0},
          target: {:ieee, @destination, 241},
          target: {:group, -1},
          target: {:group, 0xFFF8},
          target: {:group, 1, 2},
          target: nil
        ] do
      assert {:error, %Error{kind: :invalid_value, operation: :binding} = error} =
               Binding.new(options([{key, value}]))

      refute inspect(error) =~ "credential-canary"
    end

    for target <- [{:ieee, @destination, 240}, {:group, 0}, {:group, 0xFFF7}] do
      assert {:ok, request} =
               Binding.new(
                 options(route_address: 0, source_endpoint: 240, cluster: 65_535, target: target)
               )

      assert Binding.valid?(request)
    end
  end

  test "missing, duplicate, extra and copied fields fail at public input boundaries" do
    good = options()

    for candidate <- [
          nil,
          %{},
          [:bad],
          Keyword.delete(good, :target),
          [{:target, {:group, 1}} | good],
          [{:key, "credential-canary"} | good]
        ] do
      assert {:error, %Error{kind: :invalid_value}} = Binding.new(candidate)
    end

    {:ok, request} = Binding.new(good)

    for candidate <- [
          nil,
          Map.delete(request, :cluster),
          Map.put(request, :key, "credential-canary"),
          %{request | operation: :reset},
          %{request | route_address: 0xFFFF},
          %{request | target: {:ieee, @destination, nil}}
        ] do
      refute Binding.valid?(candidate)
      assert {:error, %Error{kind: :invalid_value} = error} = Binding.frame(candidate)
      refute inspect(error) =~ "credential-canary"
    end
  end

  test "exact source/status callbacks preserve peer failures and absent security metadata" do
    profile = :json.decode(File.read!(@profile))

    for vector <- profile["adoption"]["responses"] do
      operation = if vector["operation"] == "bind", do: :bind, else: :unbind
      payload = Base.decode16!(vector["payload_hex"], case: :mixed)
      assert {:ok, response} = Binding.response(operation, payload)
      assert response == %{operation: operation, source_address: 0x1234, status: vector["status"]}
      id = if operation == :bind, do: 0xA1, else: 0xA2
      event = Event.from_frame(%Frame{type: :areq, subsystem: 5, id: id, payload: payload})
      assert event.kind == if(operation == :bind, do: :zdo_bind, else: :zdo_unbind)
      assert event.payload == payload
      assert event.zdo == response
      assert event.status == response.status
      assert event.source_address == 0x1234
      assert event.security_used == nil
      assert event.transaction == nil
      assert event.source_endpoint == nil
      assert event.cluster == nil
      assert event.owner_epoch == nil
    end
  end

  test "truncation, trailing bytes and reserved callback sources remain malformed evidence" do
    for payload <- [
          nil,
          <<>>,
          <<0x34, 0x12>>,
          <<0x34, 0x12, 0, 0>>,
          <<0xFFF8::little-16, 0>>,
          <<0xFFFF::little-16, 0>>
        ] do
      assert {:error, %Error{kind: :invalid_frame}} = Binding.response(:bind, payload)

      if is_binary(payload) do
        for id <- [0xA1, 0xA2] do
          event = Event.from_frame(%Frame{type: :areq, subsystem: 5, id: id, payload: payload})
          assert event.kind == :malformed_indication
          assert event.payload == payload
          assert event.zdo == nil
        end
      end
    end

    assert {:error, _} = Binding.response(:other, <<0x34, 0x12, 0>>)
    assert {:ok, %{source_address: 0, status: 255}} = Binding.response(:unbind, <<0, 0, 255>>)
  end

  defp options(overrides \\ []) do
    Keyword.merge(
      [
        operation: :bind,
        peer_ieee: @ieee,
        route_address: 0x1234,
        source_endpoint: 1,
        cluster: 6,
        target: {:ieee, @destination, 2},
        correlation_id: "host-only-correlation"
      ],
      overrides
    )
  end
end
