defmodule Wotex.CoAP.DTLSPKIRejectionInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Error, Security}
  @moduletag :interop
  @moduletag :capture_log
  @fixtures Path.expand("../fixtures/dtls_pki", __DIR__)

  test "WCO-S05 WCO-V12 an independent peer with a rejected certificate cannot carry CoAP" do
    profile = System.fetch_env!("WOTEX_COAP_PKI_INTEROP_PROFILE")

    assert profile in [
             "wrong-san",
             "expired",
             "wrong-ku",
             "wrong-eku",
             "critical",
             "cn-only",
             "wildcard",
             "revoked"
           ]

    identity = if profile == "wildcard", do: "sensor.fixture.test", else: "fixture.test"
    crl = if profile == "revoked", do: "revoked-crl.der", else: "valid-crl.der"

    {:ok, security} =
      Security.new(
        mode: :dtls_pki,
        trust_roots: [fixture("root.der")],
        certificate: fixture("client.der"),
        private_key: fixture("client-key.der"),
        server_identity: {:dns, identity},
        crls: [fixture(crl)]
      )

    options = [
      host: "127.0.0.1",
      port: System.fetch_env!("WOTEX_COAP_DTLS_INTEROP_PORT") |> String.to_integer(),
      scheme: :coaps,
      timeout: 1000
    ]

    assert {:error, %Error{code: code, effect: :none}} =
             CoAP.connect([security: security] ++ options)

    assert code in [:security_handshake_failed, :timeout]

    {:ok, psk} = Security.new(mode: :dtls_psk, identity: "client", key: "fixture-key-12345")
    assert {:ok, session} = CoAP.connect([security: psk] ++ options)
    assert {:ok, %{code: 69}} = CoAP.get(session, "/")
    assert :ok = CoAP.disconnect(session)
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))
end
