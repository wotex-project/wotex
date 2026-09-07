defmodule Wotex.Binding.MQTT.JSONTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT.{Error, JSON}

  test "encodes and decodes bounded JSON" do
    value = %{"enabled" => true, "levels" => [1, 2, nil]}
    assert {:ok, payload} = JSON.encode(value, 100)
    assert {:ok, ^value} = JSON.decode(payload, 100)
  end

  test "rejects oversized encoded and received payloads" do
    assert {:error,
            %Error{code: :encoded_payload_too_large, class: :protocol, details: %{max_bytes: 2}}} =
             JSON.encode("value", 2)

    assert {:error, %Error{code: :received_payload_too_large}} = JSON.decode("{}", 1)
  end

  test "rejects hostile structure through the core admission limits" do
    duplicate = ~s({"value":1,"value":2})

    assert {:error, %Error{code: :json_decode_failed, class: :protocol, details: %{cause: cause}}} =
             JSON.decode(duplicate, 100)

    assert cause == :duplicate_member

    deep = String.duplicate("[", 200) <> String.duplicate("]", 200)

    assert {:error, %Error{code: :json_decode_failed, details: %{cause: :depth_limit_exceeded}}} =
             JSON.decode(deep, 1_000)

    refute inspect(JSON.decode(duplicate, 100)) =~ "value"
  end

  test "encodes the canonical Wotex form with sorted object keys" do
    assert {:ok, ~s({"a":1,"b":2})} = JSON.encode(%{"b" => 2, "a" => 1}, 100)
  end

  test "normalizes codec failures without external values" do
    assert {:error, %Error{code: :json_encode_failed, details: %{}}} = JSON.encode(self(), 100)
    assert {:error, %Error{code: :json_decode_failed, details: %{}}} = JSON.decode("{", 100)
    assert {:error, %Error{code: :invalid_json_payload}} = JSON.decode(:not_binary, 100)
    assert {:error, %Error{code: :invalid_payload_limit, class: :permanent}} = JSON.encode(nil, 0)
    assert {:error, %Error{code: :invalid_payload_limit}} = JSON.decode("null", :infinity)
  end
end
