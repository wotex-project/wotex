defmodule Wotex.BACnet.CharacterStringTest do
  @moduledoc false

  use ExUnit.Case, async: false
  use ExUnitProperties
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{Address, BACstack, CharacterString, IPv4, Tags, Value}
  @moduletag :capture_log
  @message %{type: :read_property, object_type: 1, instance: 0, property: 85}

  test "WBA-S01 WBA-V01 charset identity survives scalar and opaque values" do
    for set <- [0, 1, 2, 3, 4, 5, 255] do
      bytes = if set == 0, do: "hé", else: <<0xFF, 0>>
      assert {:ok, string} = CharacterString.new(set, bytes)
      value = Encoding.create!({:character_string, string})
      assert :ok = Value.validate_read(value)
      assert {:ok, [character_string: ^string]} = Tags.decode(char_tag(set, bytes))

      if set == 0 do
        assert {^bytes, %{bacnet_type: :character_string, character_set: 0}} = Value.result(value)
        assert :ok = Value.validate_write(value)
        assert {:character_string, ^bytes} = Value.to_tag(value)
      else
        assert {^value, %{character_set: ^set, native_value: true}} = Value.result(value)
        assert {:error, %{code: :unsupported_character_set}} = Value.validate_write(value)
      end
    end

    plain = Encoding.create!({:character_string, "normalised by external SDK"})
    assert {:error, %{code: :character_set_unavailable}} = Value.validate_read(plain)
    assert :ok = Value.validate_write(plain)

    assert {:error, %{code: :invalid_value}} =
             Value.validate_read(
               Encoding.create!(
                 {:character_string, %CharacterString{character_set: 0, bytes: <<255>>}}
               )
             )

    assert {:error, _} = CharacterString.new(256, "a")
    assert {:error, _} = CharacterString.new(0, :not_bytes)
    assert {:error, _} = CharacterString.new(1, :binary.copy("a", 65_537))
  end

  test "WBA-S01 WBA-V01 a forged CharacterString fails send validation with a typed error" do
    {:ok, session} = Wotex.BACnet.connect(client: Wotex.BACnet.TestClient)
    on_exit(fn -> Wotex.BACnet.disconnect(session) end)
    valid = %CharacterString{character_set: 0, bytes: "a"}

    nested = fn string ->
      %Encoding{encoding: :constructed, type: nil, value: {:null, string}, extras: [tag_number: 3]}
    end

    for value <- [
          nested.(%{valid | character_set: [0 | 0]}),
          nested.(%{valid | character_set: self()}),
          nested.(Map.put(valid, :extra, [1 | 2])),
          Encoding.create!({:character_string, Map.delete(valid, :bytes)}),
          Encoding.create!({:character_string, Map.put(valid, :extra, self())})
        ] do
      message = Map.merge(@message, %{type: :write_property, value: value})

      assert {:error, %{code: :invalid_value, effect: :none}} =
               Wotex.BACnet.send(session, message)

      assert {:error, %{code: :invalid_value}} = Value.validate_native(value)
    end

    assert {:ok, _} =
             Wotex.BACnet.send(
               session,
               Map.merge(@message, %{
                 type: :write_property,
                 value: Encoding.create!({:character_string, valid})
               })
             )
  end

  property "WBA-S01 WBA-V01 opaque charset values retain all bytes" do
    check all(set <- integer(1..255), bytes <- binary(max_length: 1024)) do
      assert {:ok, [character_string: %CharacterString{character_set: ^set, bytes: ^bytes}]} =
               Tags.decode(char_tag(set, bytes))
    end
  end

  test "WBA-S01 WBA-V02 malformed UTF-8, absent charset, nested and extended tags are bounded" do
    for bytes <- [
          <<0x70>>,
          <<0x71, 0xFF, 0x72>>,
          <<0x72, 0, 0xFF>>,
          <<0x75>>,
          <<0x75, 254>>,
          <<0x75, 255, 0, 0>>,
          <<0x3F>>,
          <<0x3E, 0x4F>>,
          <<0x3E>>,
          <<0xF9>>,
          <<0x76>>
        ] do
      assert {:error, %{code: :invalid_tags}} = Tags.decode(bytes)
    end

    assert {:error, %{code: :value_limit}} = Tags.decode(:bad)
    assert {:error, %{code: :value_limit}} = Tags.decode(:binary.copy(<<0>>, 65_537))
    assert {:ok, values} = Tags.decode(:binary.copy(<<0>>, 4096))
    assert length(values) == 4096
    assert {:error, _} = Tags.decode(:binary.copy(<<0>>, 4097))
    assert {:ok, _} = Tags.decode(<<0x3E>> <> :binary.copy(<<0>>, 4095) <> <<0x3F>>)
    assert {:error, _} = Tags.decode(:binary.copy(<<0x3E>>, 9) <> :binary.copy(<<0x3F>>, 9))

    assert {:ok, [{:constructed, {3, {:character_string, string}, 0}}]} =
             Tags.decode(<<0x3E>> <> char_tag(255, <<0, 255>>) <> <<0x3F>>)

    nested = Encoding.create!({:constructed, {3, {:character_string, string}, 0}})
    assert :ok = Value.validate_read(nested)
    assert {:error, %{code: :unsupported_character_set}} = Value.validate_write(nested)
    assert {:ok, [tagged: {20, <<42>>, 1}]} = Tags.decode(<<0xF9, 20, 42>>)

    assert {:ok, [character_string: %CharacterString{bytes: "x"}]} =
             Tags.decode(<<0x75, 255, 0, 0, 0, 2, 0, 120>>)
  end

  test "WBA-S01 WBA-S02 WBA-V01 WBA-V04 owned UDP retains charset through reassembly" do
    {:ok, peer} = :gen_udp.open(55_823, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)

    {:ok, handle} =
      IPv4.connect(local_ip: :none, local_port: 55_819, destination: {{127, 0, 0, 1}, port})

    on_exit(fn ->
      IPv4.disconnect(handle)
      :gen_udp.close(peer)
    end)

    group = :sys.get_state(handle.owner)
    # Unsolicited segments have no admitted invoke ID and allocate no store entry.
    send(
      group.client,
      {:bacnet_transport, {:bacnet_ipv4, BACnet.Stack.Transport.IPv4Transport},
       {{127, 0, 0, 1}, port},
       {:apdu, nil, struct(BACnet.Protocol.NPCI, source: nil), <<0x3C, 250, 0, 2, 12, 0>>},
       group.portal}
    )

    :sys.get_state(group.client)
    assert :sys.get_state(group.segments_store).sequences == %{}

    for bytes <- [<<0x3C, 250, 0, 2, 13, 0>>, <<0x0C, 0x65, 250, 0, 2, 1, 0>>] do
      send(
        group.client,
        {:bacnet_transport, {:bacnet_ipv4, BACnet.Stack.Transport.IPv4Transport},
         {{127, 0, 0, 1}, port}, {:apdu, nil, struct(BACnet.Protocol.NPCI, source: nil), bytes},
         group.portal}
      )

      :sys.get_state(group.client)
      assert :sys.get_state(group.segments_store).sequences == %{}
    end

    for segmented <- [false, true], set <- [0, 5, 255] do
      task = Task.async(fn -> IPv4.request(handle, @message, 1000) end)
      {ip, port, id} = request(peer)
      text = if set == 0, do: "hé", else: <<255, 0>>
      payload = <<0x0C, 1::10, 0::22, 0x19, 85, 0x3E>> <> char_tag(set, text) <> <<0x3F>>

      if segmented do
        <<first::binary-size(8), rest::binary>> = payload
        reply(peer, ip, port, <<0x3C, id, 0, 2, 12, first::binary>>)
        # First-segment acknowledgment proves the real store owns reassembly.
        assert {:ok, {^ip, ^port, <<0x81, 0x0A, _::16, 1, 0, 0x40, ^id, 0, 2>>}} =
                 :gen_udp.recv(peer, 0, 1000)

        reply(peer, ip, port, <<0x38, id, 1, 2, 12, rest::binary>>)

        assert {:ok, {^ip, ^port, <<0x81, 0x0A, _::16, 1, 0, 0x40, ^id, 1, 2>>}} =
                 :gen_udp.recv(peer, 0, 1000)
      else
        reply(peer, ip, port, <<0x30, id, 12, payload::binary>>)
      end

      assert {:ok, %Encoding{value: %CharacterString{character_set: ^set, bytes: ^text}}} =
               Task.await(task)

      client = :sys.get_state(handle.owner).client
      assert :sys.get_state(client).sdk.apdu_timers == %{}
      store = :sys.get_state(handle.owner).segments_store
      assert :sys.get_state(store).sequences == %{}
    end

    task = Task.async(fn -> IPv4.request(handle, @message, 1000) end)
    {ip, port, id} = request(peer)
    reply(peer, ip, port, <<0x30, id, 12, 0x0C, 1::10, 0::22, 0x19, 85, 0x3E, 0x72, 0, 255, 0x3F>>)
    assert {:error, %{code: :invalid_tags}} = Task.await(task)
    assert {:ok, address} = Address.new(@message)

    assert {:error, %{code: :invalid_tags}} =
             BACstack.response(
               {:error, Wotex.BACnet.Error.new(:invalid_tags)},
               address,
               :read_property
             )
  end

  defp char_tag(set, bytes) do
    size = byte_size(bytes) + 1

    header =
      cond do
        size <= 4 -> <<7::4, 0::1, size::3>>
        size < 254 -> <<0x75, size>>
        true -> <<0x75, 254, size::16>>
      end

    header <> <<set>> <> bytes
  end

  defp request(peer) do
    assert {:ok, {ip, port, <<0x81, 0x0A, _::16, 1, 4, _, _, id, 12, _::binary>>}} =
             :gen_udp.recv(peer, 0, 1000)

    {ip, port, id}
  end

  defp reply(peer, ip, port, apdu),
    do: :gen_udp.send(peer, ip, port, <<0x81, 0x0A, byte_size(apdu) + 6::16, 1, 0, apdu::binary>>)
end
