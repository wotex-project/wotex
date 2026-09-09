defmodule Wotex.CoAP.SecurityTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.CoAP.{Error, Security}

  test "WCO-S05 WCO-V12 explicit PSK values retain identity and key without diagnostic disclosure" do
    for identity <- ["client", "klient-ä", String.duplicate("a", 128)], size <- [16, 64] do
      key = :binary.copy(<<255>>, size)
      input = %{mode: :dtls_psk, identity: identity, key: key}
      assert {:ok, value} = Security.new(input)
      assert {:ok, ^value} = Security.new(Map.to_list(input))
      assert value.identity == identity and value.key == key
      assert :ok = Security.validate(value)
      assert inspect(value) == "#Wotex.CoAP.Security<mode: :dtls_psk, ...>"
    end
  end

  test "WCO-C02 WCO-S05 malformed and forged credential values fail without echoing input" do
    input = %{mode: :dtls_psk, identity: "PRIVATE-IDENTITY", key: "PRIVATE-KEY-12345"}

    for identity <- [nil, "", <<255>>, "a\x00b", "a\nb", "a\x7Fb", String.duplicate("a", 129)] do
      assert {:error, %Error{code: :invalid_security, field: :identity, details: %{}}} =
               Security.new(%{input | identity: identity})
    end

    for key <- [nil, :binary.copy(<<0>>, 15), :binary.copy(<<0>>, 65), ~c"secret", 123] do
      assert {:error, %Error{field: :key}} = Security.new(%{input | key: key})
    end

    for value <- [
          nil,
          %{},
          input.key,
          Map.put(input, :extra, input.key),
          %{input | mode: :unknown},
          Map.delete(input, :key),
          [mode: :dtls_psk, identity: "client", key: input.key, key: input.key],
          [{:mode, :dtls_psk} | nil],
          %{__struct__: Security, mode: :dtls_psk}
        ] do
      assert {:error, %Error{code: :invalid_security} = error} = Security.new(value)
      refute inspect(error) =~ "PRIVATE"
    end

    {:ok, value} = Security.new(input)

    for bad <- [nil, input, Map.put(value, :extra, true), %{value | key: nil}] do
      assert {:error, %Error{}} = Security.validate(bad)
    end
  end

  property "WCO-C02 WCO-S05 arbitrary PSK bytes preserve bounded deterministic admission" do
    check all(identity <- binary(max_length: 150), key <- binary(max_length: 80)) do
      result = Security.new(mode: :dtls_psk, identity: identity, key: key)
      assert result == Security.new(%{mode: :dtls_psk, identity: identity, key: key})

      case result do
        {:ok, value} -> assert :ok = Security.validate(value)
        {:error, %Error{details: details}} -> assert details == %{}
      end
    end
  end
end
