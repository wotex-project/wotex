defmodule Wotex.OPCUA.AsyncuaInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.OPCUA
  alias Wotex.OPCUA.Asyncua
  @moduletag :interop

  test "secure peer read/write/browse and certificate rejection gates" do
    path = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    config = Jason.decode!(File.read!(path))

    keys = [
      :executable,
      :endpoint,
      :certificate,
      :private_key,
      :server_certificate,
      :issuer_certificate,
      :crl,
      :trust_certificates,
      :client_uri,
      :server_uri
    ]

    opts = Enum.map(keys, &{&1, Map.fetch!(config, Atom.to_string(&1))})
    opts = [client: Asyncua, timeout: 10_000] ++ opts
    node = config["node_id"]
    assert {:ok, session} = OPCUA.connect(opts)

    assert {:ok, %{"value" => original, "status" => 0}} =
             OPCUA.send(session, %{type: :read, node_id: node})

    assert {:ok, "written"} =
             OPCUA.send(session, %{
               type: :write,
               node_id: node,
               value: %{type: "Double", value: 42.5}
             })

    assert {:ok, %{"value" => 42.5}} = OPCUA.send(session, %{type: :read, node_id: node})
    assert {:ok, children} = OPCUA.send(session, %{type: :browse, node_id: "i=85"})
    assert node in children
    assert {:error, _} = OPCUA.send(session, %{type: :read, node_id: "ns=2;s=missing"})

    assert {:ok, "written"} =
             OPCUA.send(session, %{
               type: :write,
               node_id: node,
               value: %{type: "Double", value: original}
             })

    assert :ok = OPCUA.disconnect(session)
    directory = Path.dirname(path)

    for change <- [
          [server_uri: "urn:wrong"],
          [crl: Path.join(directory, "revoked.crl")],
          [server_certificate: Path.join(directory, "expired.der")],
          [server_certificate: Path.join(directory, "wronghost.der")],
          [trust_certificates: [Path.join(directory, "client.der")]]
        ] do
      assert {:ok, session} = OPCUA.connect(Keyword.merge(opts, change))
      assert {:error, _} = OPCUA.send(session, %{type: :read, node_id: node})
      OPCUA.disconnect(session)
    end
  end
end
