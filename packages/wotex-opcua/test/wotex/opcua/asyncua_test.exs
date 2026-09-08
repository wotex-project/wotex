defmodule Wotex.OPCUA.AsyncuaTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Asyncua
  @message %{type: :read, node_id: "i=42"}

  test "security configuration is explicit and bridge results are correlated" do
    opts = options("/missing/python")
    assert {:ok, handle} = Asyncua.connect(opts)
    assert {:error, _} = Asyncua.request(handle, @message, 100)
    assert {:error, _} = Asyncua.request(handle, %{node_id: nil}, 100)
    assert {:error, _} = Asyncua.request(handle, Map.put(@message, :value, self()), 100)

    assert {:error, _} =
             Asyncua.request(handle, Map.put(@message, :value, :binary.copy("x", 131_072)), 100)

    assert :ok = Asyncua.disconnect(handle)

    for change <- [
          [executable: "relative"],
          [username: "user"],
          [security_policy: :none],
          [crl: nil],
          [server_uri: ""],
          [trust_certificates: []],
          [endpoint: "http://localhost/"],
          [security_mode: :none]
        ],
        do: assert(match?({:error, _}, Asyncua.connect(Keyword.merge(opts, change))))

    assert {:ok, 42} = Asyncua.decode(~s({"id":1,"ok":42}), 1)

    for bytes <- [
          ~s({"id":2,"ok":42}),
          ~s({"id":1,"error":"failed"}),
          ~s({"id":1,"ok":42,"error":"failed"}),
          "logs",
          nil,
          :binary.copy("x", 131_073)
        ],
        do: assert(match?({:error, _}, Asyncua.decode(bytes, 1)))
  end

  test "owned bridge bounds execution, output and abnormal child termination" do
    path = Path.join(System.tmp_dir!(), "wotex-ua-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)
    {:ok, handle} = Asyncua.connect(options(path))

    script(
      path,
      "IFS= read -r request\nid=$(printf '%s' \"$request\" | sed -n 's/.*\"id\":\\([0-9]*\\).*/\\1/p')\nprintf '{\"id\":%s,\"ok\":42}\\n' \"$id\""
    )

    assert {:ok, 42} = Asyncua.request(handle, @message, 1000)
    script(path, "exit 1")
    assert {:error, _} = Asyncua.request(handle, @message, 1000)
    script(path, "sleep 1")
    assert {:error, %{code: :timeout}} = Asyncua.request(handle, @message, 10)
    script(path, "printf '%0140000d' 0")
    assert {:error, %{code: :response_limit}} = Asyncua.request(handle, @message, 1000)
  end

  defp options(executable) do
    [
      executable: executable,
      endpoint: "opc.tcp://localhost:4840/",
      certificate: "/client.der",
      private_key: "/client.pem",
      server_certificate: "/server.der",
      issuer_certificate: "/ca.der",
      crl: "/issuer.crl",
      trust_certificates: ["/ca.der"],
      client_uri: "urn:client",
      server_uri: "urn:server"
    ]
  end

  defp script(path, body) do
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o700)
  end
end
