defmodule Wotex.CoAP.Test.RuntimeDTLSPeer do
  @moduledoc false

  alias Wotex.CoAP.{Codec, Security}
  @key "fixture-key-12345"
  @cipher %{key_exchange: :psk, cipher: :aes_128_gcm, mac: :aead, prf: :sha256}
  @pki_cipher %{key_exchange: :ecdhe_rsa, cipher: :aes_128_gcm, mac: :aead, prf: :sha256}
  @fixtures Path.expand("../fixtures/dtls_pki", __DIR__)
  @spec peer(:psk | :pki, String.t()) :: {Task.t(), term(), pos_integer()}
  def peer(mode, certificate \\ "server") do
    {:ok, _} = Application.ensure_all_started(:ssl)
    test = self()

    lookup = fn
      :psk, identity, key ->
        send(test, {:identity, identity})
        if identity == "client", do: {:ok, key}, else: :error
    end

    {:ok, listener} =
      :ssl.listen(
        0,
        [
          protocol: :dtls,
          versions: [:"dtlsv1.2"],
          mode: :binary,
          active: false,
          ip: {127, 0, 0, 1},
          log_level: :none,
          reuse_sessions: false
        ] ++
          if(mode == :psk,
            do: [ciphers: [@cipher], verify: :verify_none, user_lookup_fun: {lookup, @key}],
            else: [
              ciphers: [@pki_cipher],
              verify: :verify_peer,
              fail_if_no_peer_cert: true,
              cacerts: [fixture("root.der")],
              cert: fixture(certificate <> ".der"),
              key: {:RSAPrivateKey, fixture(certificate <> "-key.der")}
            ]
          )
      )

    {:ok, {_, port}} = :ssl.sockname(listener)

    peer =
      Task.async(fn ->
        with {:ok, accepted} <- :ssl.transport_accept(listener, 1000),
             {:ok, socket} <- :ssl.handshake(accepted, 1000) do
          :ok = :ssl.setopts(socket, active: true)
          peer_loop(socket, test)
        else
          {:error, _} -> :ok
        end
      end)

    {peer, listener, port}
  end

  defp peer_loop(socket, test) do
    receive do
      {:ssl, ^socket, bytes} ->
        {:ok, request} = Codec.decode(bytes)
        send(test, {:request, request})
        peer_loop(socket, test)

      {:reply, message} ->
        {:ok, bytes} = Codec.encode(message)
        :ok = :ssl.send(socket, bytes)
        peer_loop(socket, test)

      {:ssl_closed, ^socket} ->
        :ok

      :close ->
        :ssl.close(socket, 100)
    after
      2000 -> :ssl.close(socket, 100)
    end
  end

  @spec close_peer(Task.t(), term()) :: term()
  def close_peer(peer, listener) do
    send(peer.pid, :close)
    :ssl.close(listener, 100)
    Task.await(peer, 1500)
  end

  @spec security(:psk, keyword()) :: Security.t()
  def security(:psk, overrides \\ []) do
    {:ok, security} =
      Security.new(Keyword.merge([mode: :dtls_psk, identity: "client", key: @key], overrides))

    security
  end

  @spec pki_security(keyword()) :: Security.t()
  def pki_security(overrides \\ []) do
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
          overrides
        )
      )

    security
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))
end
