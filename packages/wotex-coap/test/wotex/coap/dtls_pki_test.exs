defmodule Wotex.CoAP.DTLSPKITest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Error, Security}
  @moduletag :capture_log
  @fixtures Path.expand("../../fixtures/dtls_pki", __DIR__)
  @cipher %{key_exchange: :ecdhe_rsa, cipher: :aes_128_gcm, mac: :aead, prf: :sha256}

  test "WCO-S05 WCO-V12 PKI authenticates explicit DNS and IP identities with supplied revocation material" do
    for identity <- [{:dns, "fixture.test"}, {:ip, {127, 0, 0, 1}}],
        key <- ["client-key.der", "client-pkcs8.der"] do
      {peer, listener, port} = peer("server")
      security = security(server_identity: identity, private_key: fixture(key))

      assert {:ok, session} =
               CoAP.connect(
                 host: "127.0.0.1",
                 port: port,
                 scheme: :coaps,
                 security: security,
                 timeout: 1000
               )

      adapter = :sys.get_state(session.pid).handle.pid
      socket = :sys.get_state(adapter).socket
      {:ok, information} = :ssl.connection_information(socket, [:selected_cipher_suite, :protocol])

      assert information[:selected_cipher_suite] == @cipher and
               information[:protocol] == :"dtlsv1.2"

      assert {:ok, %{code: 69, payload: "authenticated"}} = CoAP.get(session, "/value")
      assert_receive {:served, "server"}
      assert :ok = CoAP.disconnect(session)
      close(peer, listener)
    end
  end

  test "WCO-S05 WCO-V12 certificate validity, exact SAN, usage and critical extensions fail closed" do
    for certificate <- [
          "wrong-san",
          "expired",
          "wrong-ku",
          "wrong-eku",
          "critical",
          "cn-only",
          "wildcard",
          "weak"
        ] do
      {peer, listener, port} = peer(certificate)

      identity =
        if certificate == "wildcard",
          do: {:dns, "sensor.fixture.test"},
          else: {:dns, "fixture.test"}

      assert {:error, %Error{effect: :none}} =
               CoAP.connect(
                 host: "127.0.0.1",
                 port: port,
                 scheme: :coaps,
                 security: security(server_identity: identity),
                 timeout: 500
               )

      refute_received {:served, _}
      close(peer, listener)
    end
  end

  test "WCO-S05 WCO-V12 revoked certificates and invalid CRL signatures cannot authenticate" do
    valid = fixture("valid-crl.der")
    prefix_size = byte_size(valid) - 1
    <<prefix::binary-size(^prefix_size), last>> = valid
    tampered = <<prefix::binary, Bitwise.bxor(last, 1)>>

    for {certificate, crl} <- [{"revoked", fixture("revoked-crl.der")}, {"server", tampered}] do
      {peer, listener, port} = peer(certificate)

      assert {:error, %Error{effect: :none}} =
               CoAP.connect(
                 host: "127.0.0.1",
                 port: port,
                 scheme: :coaps,
                 security: security(crls: [crl]),
                 timeout: 500
               )

      refute_received {:served, _}
      close(peer, listener)
    end
  end

  test "WCO-S05 WCO-V12 an unrelated trust root or expired CRL cannot authenticate a peer" do
    for options <- [
          [trust_roots: [fixture("untrusted-root.der")]],
          [crls: [fixture("expired-crl.der")]]
        ] do
      {peer, listener, port} = peer("server")

      assert {:error, %Error{effect: :none}} =
               CoAP.connect(
                 host: "127.0.0.1",
                 port: port,
                 scheme: :coaps,
                 security: security(options),
                 timeout: 500
               )

      refute_received {:served, _}
      close(peer, listener)
    end
  end

  test "WCO-S05 supplied CRL snapshots remain isolated between simultaneously owned sessions" do
    {first_peer, first_listener, first_port} = peer("revoked")

    {:ok, first} =
      CoAP.connect(
        host: "127.0.0.1",
        port: first_port,
        scheme: :coaps,
        security: security(crls: [fixture("valid-crl.der")]),
        timeout: 1000
      )

    {second_peer, second_listener, second_port} = peer("revoked")

    assert {:error, %Error{effect: :none}} =
             CoAP.connect(
               host: "127.0.0.1",
               port: second_port,
               scheme: :coaps,
               security: security(crls: [fixture("revoked-crl.der")]),
               timeout: 500
             )

    close(second_peer, second_listener)
    assert {:ok, %{payload: "authenticated"}} = CoAP.get(first, "/isolated")
    assert :ok = CoAP.disconnect(first)
    close(first_peer, first_listener)
  end

  defp peer(name) do
    {:ok, _} = Application.ensure_all_started(:ssl)
    test = self()

    {:ok, listener} =
      :ssl.listen(0,
        protocol: :dtls,
        versions: [:"dtlsv1.2"],
        ciphers: [@cipher],
        verify: :verify_peer,
        fail_if_no_peer_cert: true,
        cacerts: [fixture("root.der")],
        cert: fixture(name <> ".der"),
        key: {:RSAPrivateKey, fixture(name <> "-key.der")},
        active: false,
        mode: :binary,
        ip: {127, 0, 0, 1},
        log_level: :none,
        reuse_sessions: false
      )

    {:ok, {_, port}} = :ssl.sockname(listener)

    peer =
      Task.async(fn ->
        with {:ok, accepted} <- :ssl.transport_accept(listener, 1000),
             {:ok, socket} <- :ssl.handshake(accepted, 1000),
             {:ok, bytes} <- :ssl.recv(socket, 0, 1000) do
          {:ok, request} = Codec.decode(bytes)

          {:ok, reply} =
            Codec.encode(%{
              request
              | type: :ack,
                code: 69,
                options: [{12, <<42>>}],
                payload: "authenticated"
            })

          :ok = :ssl.send(socket, reply)
          send(test, {:served, name})

          receive do
            :close -> :ssl.close(socket, 100)
          after
            1000 -> :ssl.close(socket, 100)
          end
        else
          {:error, _} -> :ok
        end
      end)

    {peer, listener, port}
  end

  defp close(peer, listener) do
    send(peer.pid, :close)
    :ssl.close(listener, 100)
    Task.await(peer, 1500)
  end

  defp security(options) do
    {:ok, value} =
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
          options
        )
      )

    value
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))
end
