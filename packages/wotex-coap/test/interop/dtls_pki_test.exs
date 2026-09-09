defmodule Wotex.CoAP.DTLSPKIInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Error, Security}
  @moduletag :interop
  @moduletag :capture_log
  @fixtures Path.expand("../fixtures/dtls_pki", __DIR__)

  test "WCO-S05 WCO-V12 libcoap PKI authenticates exact DNS/IP identities and both RSA encodings" do
    for identity <- [{:dns, "fixture.test"}, {:ip, {127, 0, 0, 1}}],
        key <- ["client-key.der", "client-pkcs8.der"] do
      {:ok, session} = connect(server_identity: identity, private_key: fixture(key))

      try do
        adapter = :sys.get_state(session.pid).handle.pid
        socket = :sys.get_state(adapter).socket

        assert {:ok, information} =
                 :ssl.connection_information(socket, [:protocol, :selected_cipher_suite])

        assert information[:protocol] == :"dtlsv1.2"

        assert information[:selected_cipher_suite] == %{
                 key_exchange: :ecdhe_rsa,
                 cipher: :aes_128_gcm,
                 mac: :aead,
                 prf: :sha256
               }

        body = :binary.copy("pki-authenticated", 200)

        assert {:ok, %{code: code, payload: ^body}} =
                 CoAP.put(session, "/wotex-pki", body, content_format: 42)

        assert code in [65, 68]
        assert {:ok, %{code: 69, payload: ^body}} = CoAP.get(session, "/wotex-pki", accept: 42)
        assert {:ok, %{code: 66}} = CoAP.delete(session, "/wotex-pki")
      after
        assert :ok = CoAP.disconnect(session)
      end
    end
  end

  test "WCO-S05 WCO-V12 libcoap cannot authenticate with untrusted, stale or mismatched client policy" do
    valid = fixture("valid-crl.der")
    size = byte_size(valid) - 1
    <<prefix::binary-size(^size), last>> = valid
    tampered = <<prefix::binary, Bitwise.bxor(last, 1)>>

    for changes <- [
          [server_identity: {:dns, "other.test"}],
          [trust_roots: [fixture("untrusted-root.der")]],
          [crls: [fixture("expired-crl.der")]],
          [crls: [tampered]]
        ] do
      assert {:error, %Error{code: code, effect: :none}} = connect(changes)
      assert code in [:security_handshake_failed, :timeout]
    end

    {:ok, session} = connect()
    assert {:ok, %{code: 69}} = CoAP.get(session, "/")
    assert :ok = CoAP.disconnect(session)
  end

  test "WCO-S02 WCO-S03 WCO-S05 WCO-V15 libcoap PKI Observe delivers complete updates then cancels" do
    {:ok, writer} = connect()
    {:ok, observer} = connect([], observation_options: [accept: 42])

    try do
      assert {:ok, %{code: code}} =
               CoAP.put(writer, "/wotex-pki-observe", "initial", content_format: 42)

      assert code in [65, 68]

      assert {:ok, handle} =
               CoAP.subscribe(observer, %{
                 path: "/wotex-pki-observe",
                 receiver: self(),
                 renew: false,
                 max_queue_length: 10
               })

      reference = handle.reference
      assert_receive {:wotex_coap, ^reference, {:ok, %{payload: "initial"}, _}}, 1000
      body = :binary.copy("pki-observed", 200)

      assert {:ok, %{code: 68}} =
               CoAP.put(writer, "/wotex-pki-observe", body, content_format: 42)

      assert_receive {:wotex_coap, ^reference, {:ok, %{payload: ^body}, _}}, 1500
      assert :ok = CoAP.unsubscribe(observer, handle)

      assert {:ok, %{code: 68}} =
               CoAP.put(writer, "/wotex-pki-observe", "after-cancel", content_format: 42)

      refute_receive {:wotex_coap, ^reference, _}, 50
      assert {:ok, %{code: 66}} = CoAP.delete(writer, "/wotex-pki-observe")
    after
      assert :ok = CoAP.disconnect(observer)
      assert :ok = CoAP.disconnect(writer)
    end
  end

  defp connect(changes \\ [], options \\ []) do
    {:ok, security} =
      Security.new(
        Keyword.merge(
          [
            mode: :dtls_pki,
            trust_roots: [fixture("root.der")],
            certificate: fixture("client.der"),
            private_key: fixture("client-key.der"),
            server_identity: {:dns, "fixture.test"},
            crls: [fixture("valid-crl.der")]
          ],
          changes
        )
      )

    CoAP.connect(
      [
        host: "127.0.0.1",
        port: System.fetch_env!("WOTEX_COAP_DTLS_INTEROP_PORT") |> String.to_integer(),
        scheme: :coaps,
        security: security,
        timeout: 1000
      ] ++ options
    )
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))
end
