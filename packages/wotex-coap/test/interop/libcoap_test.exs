defmodule Wotex.CoAP.LibcoapTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.Error
  @moduletag :interop

  test "independent libcoap server replies over UDP with content and not-found status" do
    port = System.fetch_env!("WOTEX_COAP_INTEROP_PORT") |> String.to_integer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 3000)

    try do
      assert {:ok, %{code: 69, payload: payload}} = CoAP.send(session, %{method: :get, path: "/"})
      assert byte_size(payload) > 0

      assert {:error, %Error{code: :remote_response, details: %{code: 132}}} =
               CoAP.send(session, %{method: :get, path: "/missing-fixture"})

      assert {:ok, %{code: 69}} = CoAP.send(session, %{method: :get, path: "/.well-known/core"})
    after
      CoAP.disconnect(session)
    end
  end

  test "independent libcoap negotiates complete Block1 and Block2 bodies" do
    port = System.fetch_env!("WOTEX_COAP_INTEROP_PORT") |> String.to_integer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 5000)
    path = "/wotex-blockwise-#{System.unique_integer([:positive])}"
    body = :binary.copy("independent-block-transfer", 200)

    try do
      assert {:ok, %{code: code, payload: ^body}} =
               CoAP.send(
                 session,
                 %{method: :put, path: path, payload: body, content_format: :octet_stream}
               )

      assert code in [65, 68]
      assert {:ok, %{code: 69, payload: ^body}} = CoAP.send(session, %{method: :get, path: path})
      assert {:ok, %{code: 66}} = CoAP.send(session, %{method: :delete, path: path})

      assert {:error, %Error{code: :remote_response, details: %{code: 132}}} =
               CoAP.send(session, %{method: :get, path: path})
    after
      CoAP.disconnect(session)
    end
  end
end
