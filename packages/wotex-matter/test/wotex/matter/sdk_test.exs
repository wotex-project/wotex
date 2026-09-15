defmodule Wotex.Matter.SDKTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Matter.SDK
  @message %{type: :read, fabric_id: 1, node_id: 3, endpoint: 2, cluster: 6, member: 0}

  test "security configuration is explicit and bridge results are correlated" do
    opts = options("/missing/python")
    assert {:ok, handle} = SDK.connect(opts)
    assert {:error, _} = SDK.request(handle, @message, 100)
    assert {:error, _} = SDK.request(handle, %{node_id: nil}, 100)
    assert {:error, _} = SDK.request(%{}, @message, 100)
    assert {:error, _} = SDK.request(handle, @message, 0)

    assert {:error, _} =
             SDK.request(
               handle,
               @message
               |> Map.put(:type, :write)
               |> Map.put(:value, true)
               |> Map.put(:timed_request_timeout_ms, 101),
               100
             )

    assert {:error, _} = SDK.request(handle, Map.put(@message, :value, self()), 100)

    assert {:error, _} =
             SDK.request(handle, Map.put(@message, :value, :binary.copy("x", 131_072)), 100)

    assert :ok = SDK.disconnect(handle)
    assert {:error, _} = SDK.connect(nil)
    assert {:error, _} = SDK.connect([:not_a_keyword])
    assert {:error, _} = SDK.connect(Keyword.put(opts, :factory, nil))

    for change <- [
          [executable: "relative"],
          [username: "user"],
          [security_policy: :none],
          [fabric_id: 0],
          [factory: "invalid"],
          [settings: nil],
          [endpoint: "http://localhost/"],
          [security_mode: :none]
        ],
        do: assert(match?({:error, _}, SDK.connect(Keyword.merge(opts, change))))

    assert {:ok, 42} = SDK.decode(~s({"id":1,"ok":42}), 1)

    for bytes <- [
          ~s({"id":2,"ok":42}),
          ~s({"id":1,"error":"failed"}),
          ~s({"id":1,"ok":42,"error":"failed"}),
          "logs",
          nil,
          :binary.copy("x", 131_073)
        ],
        do: assert(match?({:error, _}, SDK.decode(bytes, 1)))
  end

  test "owned bridge bounds execution, output and abnormal child termination" do
    path = Path.join(System.tmp_dir!(), "wotex-matter-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)
    {:ok, handle} = SDK.connect(options(path))

    script(
      path,
      "IFS= read -r request\nid=$(printf '%s' \"$request\" | sed -n 's/.*\"id\":\\([0-9]*\\).*/\\1/p')\nprintf '{\"id\":%s,\"ok\":42}\\n' \"$id\""
    )

    assert {:ok, 42} = SDK.request(handle, @message, 1000)
    script(path, "exit 1")
    assert {:error, _} = SDK.request(handle, @message, 1000)
    script(path, "sleep 1")
    assert {:error, %{code: :timeout}} = SDK.request(handle, @message, 10)
    script(path, "IFS= read -r request\nprintf '%0140000d' 0")
    assert {:error, %{code: :response_limit}} = SDK.request(handle, @message, 1000)
  end

  defp options(executable) do
    [executable: executable, factory: "sdk_host:controller", settings: %{}, fabric_id: 1]
  end

  defp script(path, body) do
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o700)
  end
end
