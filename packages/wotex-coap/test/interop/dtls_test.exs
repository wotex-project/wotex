defmodule Wotex.CoAP.DTLSInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Error, Security}
  @moduletag :interop
  @moduletag :capture_log
  @key "fixture-key-12345"

  test "WCO-S05 WCO-V12 libcoap authenticates the exact PSK suite and complete blockwise operations" do
    session = connect()
    adapter = :sys.get_state(session.pid).handle.pid
    socket = :sys.get_state(adapter).socket

    assert {:ok, information} =
             :ssl.connection_information(socket, [:protocol, :selected_cipher_suite])

    assert information[:protocol] == :"dtlsv1.2"

    assert information[:selected_cipher_suite] == %{
             key_exchange: :psk,
             cipher: :aes_128_gcm,
             mac: :aead,
             prf: :sha256
           }

    body = :binary.copy("authenticated-libcoap", 200)

    try do
      assert {:ok, %{code: 69, payload: root}} = CoAP.get(session, "/")
      assert byte_size(root) > 0

      assert {:ok, %{code: code, payload: ^body}} =
               CoAP.put(session, "/wotex-dtls", body, content_format: 42)

      assert code in [65, 68]
      assert {:ok, %{code: 69, payload: ^body}} = CoAP.get(session, "/wotex-dtls", accept: 42)
      assert {:ok, %{code: 66}} = CoAP.delete(session, "/wotex-dtls")

      assert {:error, %Error{code: :remote_response, details: %{code: 132}}} =
               CoAP.get(session, "/wotex-dtls")
    after
      assert :ok = CoAP.disconnect(session)
    end
  end

  test "WCO-S05 WCO-V12 libcoap rejects mismatched identity and key without a cleartext fallback" do
    for changes <- [[identity: "wrong"], [key: "wrong-key-1234567"]] do
      {:ok, security} =
        Security.new(Keyword.merge([mode: :dtls_psk, identity: "client", key: @key], changes))

      assert {:error, %Error{code: code, effect: :none}} =
               CoAP.connect(
                 host: "127.0.0.1",
                 port: port(),
                 scheme: :coaps,
                 security: security,
                 timeout: 500
               )

      assert code in [:security_handshake_failed, :timeout]
    end

    session = connect()
    assert {:ok, %{code: 69}} = CoAP.get(session, "/")
    assert :ok = CoAP.disconnect(session)
  end

  test "WCO-S02 WCO-S03 WCO-S05 WCO-V15 libcoap Observe survives an authenticated mutation and cancels" do
    writer = connect()

    assert {:ok, %{code: code}} =
             CoAP.put(writer, "/wotex-dtls-observe", "initial", content_format: 42)

    assert code in [65, 68]
    observer = connect(observation_options: [accept: 42])

    try do
      assert {:ok, handle} =
               CoAP.subscribe(observer, %{
                 path: "/wotex-dtls-observe",
                 receiver: self(),
                 renew: false,
                 max_queue_length: 10
               })

      assert_receive {:wotex_coap, reference, {:ok, %{payload: "initial"}, _}}, 1000
      assert reference == handle.reference

      assert {:ok, %{code: 68}} =
               CoAP.put(writer, "/wotex-dtls-observe", "updated", content_format: 42)

      assert_receive {:wotex_coap, ^reference, {:ok, %{payload: "updated"}, _}}, 1500
      assert :ok = CoAP.unsubscribe(observer, handle)

      assert {:ok, %{code: 68}} =
               CoAP.put(writer, "/wotex-dtls-observe", "after-cancel", content_format: 42)

      refute_receive {:wotex_coap, ^reference, {:ok, _, _}}, 50
      assert {:ok, %{code: 66}} = CoAP.delete(writer, "/wotex-dtls-observe")
    after
      assert :ok = CoAP.disconnect(observer)
      assert :ok = CoAP.disconnect(writer)
    end
  end

  defp connect(options \\ []) do
    {:ok, security} = Security.new(mode: :dtls_psk, identity: "client", key: @key)

    {:ok, session} =
      CoAP.connect(
        [host: "127.0.0.1", port: port(), scheme: :coaps, security: security, timeout: 3000] ++
          options
      )

    session
  end

  defp port, do: System.fetch_env!("WOTEX_COAP_DTLS_INTEROP_PORT") |> String.to_integer()
end
