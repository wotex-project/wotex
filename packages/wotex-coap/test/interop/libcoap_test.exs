defmodule Wotex.CoAP.LibcoapTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  @moduletag :interop

  test "independent libcoap server replies over UDP with content and not-found status" do
    port = System.fetch_env!("WOTEX_COAP_INTEROP_PORT") |> String.to_integer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 3000)

    try do
      assert {:ok, %{code: 69, payload: payload}} = CoAP.send(session, %{method: :get, path: "/"})
      assert byte_size(payload) > 0
      assert {:ok, %{code: 132}} = CoAP.send(session, %{method: :get, path: "/missing-fixture"})
      assert {:ok, %{code: 69}} = CoAP.send(session, %{method: :get, path: "/.well-known/core"})
    after
      CoAP.disconnect(session)
    end
  end
end
