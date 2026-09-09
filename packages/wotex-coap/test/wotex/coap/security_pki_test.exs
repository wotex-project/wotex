defmodule Wotex.CoAP.SecurityPKITest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.CoAP.{Error, Security}
  alias Wotex.CoAP.Security.PKI
  @fixtures Path.expand("../../fixtures/dtls_pki", __DIR__)

  test "WCO-S05 WCO-V12 pure PKI admission accepts explicit DER material and matching RSA keys" do
    for key <- ["client-key.der", "client-pkcs8.der"],
        identity <- [
          {:dns, "fixture.test"},
          {:dns, "Fixture.Test"},
          {:ip, {127, 0, 0, 1}},
          {:ip, {0, 0, 0, 0, 0, 0, 0, 1}}
        ] do
      input = %{input() | private_key: fixture(key), server_identity: identity}
      assert {:ok, value} = Security.new(input)
      assert {:ok, ^value} = Security.new(Map.to_list(input))
      assert value.trust_roots == input.trust_roots and value.private_key == input.private_key
      assert :ok = Security.validate(value)
      assert inspect(value) == "#Wotex.CoAP.Security<mode: :dtls_pki, ...>"
    end

    assert {:ok, _} =
             Security.new(%{
               input()
               | trust_roots: List.duplicate(fixture("root.der"), 8),
                 crls: List.duplicate(fixture("valid-crl.der"), 8)
             })
  end

  test "WCO-C02 WCO-S05 malformed, mismatched and excessive PKI material fails without echoing it" do
    input = input()

    for {key, value} <- [
          {:certificate, nil},
          {:certificate, fixture("client.der") <> <<0>>},
          {:certificate, :binary.copy(<<48>>, 65_537)},
          {:certificate, fixture("weak.der")},
          {:certificate, fixture("root.der")},
          {:certificate, <<48, 129>>},
          {:private_key, fixture("server-key.der")},
          {:private_key, fixture("weak-key.der")},
          {:private_key, fixture("client-key.der") <> <<0>>},
          {:private_key, <<48, 129, 0>>},
          {:private_key, <<48, 128, 0>>},
          {:private_key, nil},
          {:crls, []},
          {:trust_roots, []},
          {:crls, [fixture("root.der")]},
          {:crls, ["invalid"]},
          {:crls, List.duplicate(fixture("valid-crl.der"), 9)},
          {:trust_roots, List.duplicate(fixture("root.der"), 9)},
          {:trust_roots, [fixture("root.der") | nil]},
          {:trust_roots, [nil]},
          {:trust_roots, [fixture("weak.der")]},
          {:trust_roots, ["invalid"]},
          {:server_identity, nil},
          {:server_identity, "fixture.test"}
        ] do
      assert {:error, %Error{code: :invalid_security, details: %{}} = error} =
               Security.new(Map.put(input, key, value))

      refute inspect(error) =~ "BEGIN"
    end

    {:ok, value} = Security.new(input)

    for bad <- [
          %{value | identity: "cross-mode"},
          %{value | key: <<0::128>>},
          Map.put(value, :extra, true),
          %{value | mode: :invalid}
        ] do
      assert {:error, %Error{code: :invalid_security}} = Security.validate(bad)
    end

    huge = :binary.copy(<<0>>, 65_536)

    assert {:error, %Error{}} =
             Security.new(%{
               input
               | trust_roots: List.duplicate(huge, 8),
                 crls: List.duplicate(huge, 8)
             })

    ec_key = :public_key.generate_key({:namedCurve, {1, 2, 840, 10_045, 3, 1, 7}})
    ec_der = :public_key.der_encode(:PrivateKeyInfo, ec_key)
    assert {:error, %Error{}} = Security.new(%{input | private_key: ec_der})

    assert {:error, %Error{}} = Security.new(Map.put(input, :identity, "cross-mode"))
    assert {:error, %Error{}} = Security.new(Map.delete(input, :crls))
    assert {:error, %Error{}} = Security.new([{:crls, input.crls} | Map.to_list(input)])
    refute PKI.strong_certificate?(:invalid)
    assert PKI.private_key(<<48, 0>>) == :error
  end

  test "WCO-S05 RSA private parameters must be coherent before any handshake can start" do
    key = :public_key.der_decode(:RSAPrivateKey, fixture("client-key.der"))

    for index <- 2..10 do
      bad = put_elem(key, index, if(index == 10, do: [], else: 1))
      bytes = :public_key.der_encode(:RSAPrivateKey, bad)

      assert {:error, %Error{code: :invalid_security}} =
               Security.new(%{input() | private_key: bytes})
    end

    decoded = :public_key.pkix_decode_cert(fixture("client.der"), :otp)
    assert PKI.strong_certificate?(decoded)
    refute PKI.strong_certificate?(put_elem(decoded, 1, :invalid))
  end

  test "WCO-S05 exact server names reject wildcards, controls, ambiguous address forms and invalid labels" do
    for identity <- [
          {:dns, ""},
          {:dns, "*.fixture.test"},
          {:dns, "fixture.test."},
          {:dns, "two..labels"},
          {:dns, "-bad.test"},
          {:dns, "bad-.test"},
          {:dns, "bad_name"},
          {:dns, "å.test"},
          {:dns, "a\x00b"},
          {:dns, <<255>>},
          {:dns, String.duplicate("x", 64)},
          {:dns, String.duplicate("x.", 128)},
          {:dns, ~c"fixture.test"},
          {:ip, {256, 0, 0, 1}},
          {:ip, {0, 0, 0, -1}},
          {:ip, {1, 2, 3}},
          {:ip, {0, 0, 0, 0, 0, 0, 0, 65_536}},
          {:ip, {0, 0, 0, :one}},
          :invalid
        ] do
      refute PKI.valid_identity?(identity)
      assert {:error, %Error{}} = Security.new(%{input() | server_identity: identity})
    end
  end

  test "WCO-S05 public certificate fixtures match their independent producer manifest" do
    {:ok, manifest} = Wotex.JSON.decode(File.read!(Path.join(@fixtures, "manifest.json")))
    assert manifest["purpose"] == "public test-only credentials"

    for {file, digest} <- manifest["files"] do
      assert Base.encode16(:crypto.hash(:sha256, fixture(file)), case: :lower) == digest
    end
  end

  property "WCO-C02 WCO-S05 arbitrary bounded DER input cannot escape structured validation" do
    check all(bytes <- binary(max_length: 2048)) do
      values = %{input() | certificate: bytes}
      assert {:error, %Error{code: :invalid_security, details: %{}}} = Security.new(values)
    end
  end

  defp input do
    %{
      mode: :dtls_pki,
      trust_roots: [fixture("root.der")],
      certificate: fixture("client.der"),
      private_key: fixture("client-key.der"),
      server_identity: {:dns, "fixture.test"},
      crls: [fixture("valid-crl.der")]
    }
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))
end
