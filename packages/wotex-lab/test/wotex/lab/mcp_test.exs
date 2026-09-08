defmodule Wotex.Lab.MCPTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab
  alias Wotex.Lab.Adapters.Runtime.StaticRef
  alias Wotex.Lab.Error
  alias Wotex.Lab.MCP.Plug, as: MCPPlug
  alias Wotex.Lab.MCP.{Resources, Seams, Server, Stdio, Tools}
  alias Wotex.Lab.Reference.Thing
  alias Wotex.ThingDescription

  @token "mcp-write-token-0123456789abcdef"
  @valid ~s({"@context":"https://www.w3.org/2022/wot/td/v1.1","id":"urn:wotex:lab:mcp:1","title":"MCP","security":["nosec_sc"],"securityDefinitions":{"nosec_sc":{"scheme":"nosec"}},"properties":{"temperature":{"type":"number","forms":[{"href":"loopback://mcp/temperature"}]}}})

  defp request(id, method, params \\ %{}),
    do: %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

  defp session(opts \\ []) do
    {:ok, state} = Server.new(opts)

    {reply, state} =
      Server.handle(state, request(1, "initialize", %{"protocolVersion" => "2025-11-25"}))

    assert reply["result"]["protocolVersion"] == "2025-11-25"

    {nil, state} =
      Server.handle(state, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    state
  end

  defp call(state, name, arguments) do
    {reply, state} =
      Server.handle(state, request(7, "tools/call", %{"name" => name, "arguments" => arguments}))

    {reply, state}
  end

  defp start_thing(lab) do
    {:ok, td} =
      Application.app_dir(:wotex_lab, "priv/fixtures/loopback/thing-description.json")
      |> File.read!()
      |> ThingDescription.parse()

    {:ok, thing} =
      Lab.start_child(
        lab,
        :things,
        {Thing,
         td: td, state: %{"temperature" => 20.5, "target" => 21.0}, tokens: %{"bearer_sc" => "t"}}
      )

    {ThingDescription.id(td), thing}
  end

  test "initialize, ping, unknown methods and malformed requests follow JSON-RPC" do
    state = session()
    assert state.initialized
    assert {%{"result" => %{}}, _} = Server.handle(state, request(2, "ping"))

    assert {%{"error" => %{"code" => -32_601}}, _} =
             Server.handle(state, request(3, "prompts/list"))

    assert {%{"error" => %{"code" => -32_600}}, _} =
             Server.handle(state, %{"jsonrpc" => "2.0", "id" => 4})

    assert {%{"error" => %{"code" => -32_600, "message" => _}}, _} =
             Server.handle(state, %{"hello" => "world"})

    assert {%{"error" => %{"code" => -32_602}}, _} =
             Server.handle(state, %{
               "jsonrpc" => "2.0",
               "id" => 5,
               "method" => "ping",
               "params" => []
             })

    assert {nil, ^state} =
             Server.handle(state, %{"jsonrpc" => "2.0", "method" => "notifications/progress"})

    assert {%{"error" => %{"code" => -32_602}}, _} =
             Server.handle(state, request(6, "resources/read", %{}))

    assert {%{"error" => %{"code" => -32_602}}, _} =
             Server.handle(state, request(6, "tools/call", %{}))

    assert {%{"error" => %{"code" => -32_602}}, _} =
             Server.handle(state, request(6, "tools/call", %{"name" => "ping", "arguments" => 1}))

    {reply, _} =
      Server.handle(state, request(8, "initialize", %{"protocolVersion" => "2024-11-05"}))

    assert reply["result"]["protocolVersion"] == Server.protocol_version()

    assert {:error, %Error{code: :write_token_required}} = Server.new(writes: true)

    assert {:error, %Error{code: :write_token_required}} =
             Server.new(writes: true, write_token: "short")

    assert {:error, %Error{code: :invalid_options}} = Server.new(writes: :yes)
  end

  test "resources list package documents, fixtures, models, tokens and seams and read them bounded" do
    state = session()
    {reply, _} = Server.handle(state, request(2, "resources/list"))
    uris = Enum.map(reply["result"]["resources"], & &1["uri"])

    assert "wotex-lab://catalogue" in uris and "wotex-lab://seams" in uris and
             "wotex-lab://models" in uris

    for uri <- uris do
      {reply, _} = Server.handle(state, request(3, "resources/read", %{"uri" => uri}))
      assert [%{"uri" => ^uri, "mimeType" => mime, "text" => text}] = reply["result"]["contents"]
      assert is_binary(mime) and byte_size(text) > 0
    end

    {reply, _} =
      Server.handle(state, request(4, "resources/read", %{"uri" => "wotex-lab://design-tokens"}))

    assert {:ok, %{"version" => _, "tokens" => %{"base" => _}}} =
             Wotex.JSON.decode(hd(reply["result"]["contents"])["text"])

    assert {%{"error" => %{"code" => -32_002}}, _} =
             Server.handle(state, request(5, "resources/read", %{"uri" => "wotex-lab://nope"}))

    assert {%{"error" => %{"code" => -32_002}}, _} =
             Server.handle(
               state,
               request(5, "resources/read", %{"uri" => "wotex-lab://things/urn:missing"})
             )

    assert {:error, -32_000, _} =
             Resources.read(state, "wotex-lab://catalogue")
             |> then(fn {:ok, _} -> {:error, -32_000, "forced"} end)

    assert Enum.map(Seams.all(), & &1["id"]) |> length() == 8
    assert {:ok, %{"owner" => "wotex_binding_http"}} = Seams.fetch("redirects")
    assert :error = Seams.fetch("teleport")
  end

  test "read tools parse documents, explain errors and answer seams; writes are absent" do
    state = session()
    {reply, _} = Server.handle(state, request(2, "tools/list"))
    names = Enum.map(reply["result"]["tools"], & &1["name"])
    assert "parse_td" in names and "explain_seam" in names and "read_property" in names
    refute "invoke_action" in names

    {reply, state} = call(state, "parse_td", %{"document" => @valid})
    assert reply["result"]["isError"] == false
    assert reply["result"]["structuredContent"]["document"]["id"] == "urn:wotex:lab:mcp:1"
    assert [%{"type" => "text", "text" => text}] = reply["result"]["content"]
    assert {:ok, %{"accepted" => true}} = Wotex.JSON.decode(text)

    {reply, state} = call(state, "parse_td", %{"document" => ~s({"title":"x"})})
    assert reply["result"]["isError"] == true

    assert [%{"code" => "schema_violation", "phase" => "schema", "path" => _} | _] =
             reply["result"]["structuredContent"]["errors"]

    {reply, state} = call(state, "parse_td", %{"document" => "{"})
    assert [%{"code" => "invalid_json"}] = reply["result"]["structuredContent"]["errors"]

    {reply, state} =
      call(state, "parse_tm", %{
        "document" =>
          ~s({"@context":"https://www.w3.org/2022/wot/td/v1.1","@type":"tm:ThingModel","title":"TM"})
      })

    assert is_boolean(reply["result"]["isError"])
    {reply, state} = call(state, "parse_td", %{"document" => String.duplicate("x", 1_048_577)})
    assert reply["error"]["code"] == -32_602
    {reply, state} = call(state, "parse_td", %{"document" => 1})
    assert reply["error"]["code"] == -32_602

    {reply, state} =
      call(state, "explain_error", %{
        "code" => "schema_violation",
        "phase" => "schema",
        "path" => "/security"
      })

    assert reply["result"]["structuredContent"]["explanation"] =~ "JSON Schema"
    {reply, state} = call(state, "explain_error", %{"code" => "x", "phase" => "unknown"})
    assert reply["result"]["structuredContent"]["explanation"] =~ "unknown phase"

    {reply, state} = call(state, "explain_seam", %{"seam" => "nx-effects"})
    assert reply["result"]["structuredContent"]["owner"] == "wotex_lab"
    {reply, state} = call(state, "explain_seam", %{"seam" => "teleport"})
    assert reply["result"]["isError"] and reply["result"]["structuredContent"]["known"] != []

    {reply, state} =
      call(state, "conformance_observe", %{
        "operation" => "parse_td",
        "document" => %{"title" => "x"}
      })

    assert reply["result"]["structuredContent"]["outcome"] in ["observed", "unsupported"]

    {reply, state} =
      call(state, "conformance_observe", %{
        "operation" => "parse_td",
        "document" => %{},
        "projection" => [1]
      })

    assert reply["error"]["code"] == -32_602

    {reply, state} = call(state, "list_things", %{})
    assert reply["result"]["structuredContent"] == %{"things" => [], "instance" => "none"}

    {reply, state} =
      call(state, "read_property", %{"thing_id" => "urn:x", "property" => "temperature"})

    assert reply["error"]["code"] == -32_002

    {reply, state} =
      call(state, "read_property", %{
        "thing_id" => "urn:x",
        "property" => "temperature",
        "deadline_ms" => 0
      })

    assert reply["error"]["code"] == -32_602

    {reply, state} =
      call(state, "verify_control_model", %{"variant" => "safe", "property" => "no_stale_dispatch"})

    assert reply["result"]["structuredContent"]["status"] == "unsupported"

    {reply, state} =
      call(state, "invoke_action", %{
        "thing_id" => "urn:x",
        "action" => "setTarget",
        "authorization" => @token,
        "idempotency_key" => "k"
      })

    assert reply["error"]["code"] == -32_601
    {reply, state} = call(state, "teleport", %{})
    assert reply["error"]["code"] == -32_601
    {reply, _state} = call(state, "explain_seam", %{})
    assert reply["error"]["code"] == -32_602
  end

  test "an explicit instance exposes its simulated Things to list, read and resource reads" do
    lab = start_supervised!({Lab, id: "mcp-things", max_children: 4})
    {id, _thing} = start_thing(lab)
    state = session(instance: lab)

    {reply, _} = Server.handle(state, request(2, "resources/list"))
    assert Enum.any?(reply["result"]["resources"], &(&1["uri"] == "wotex-lab://things/" <> id))

    {reply, _} =
      Server.handle(state, request(3, "resources/read", %{"uri" => "wotex-lab://things/" <> id}))

    assert [%{"mimeType" => "application/td+json", "text" => text}] = reply["result"]["contents"]
    assert {:ok, %{"id" => ^id}} = Wotex.JSON.decode(text)

    {reply, state} = call(state, "list_things", %{})

    assert [%{"id" => ^id, "transport" => "loopback", "actions" => ["setTarget"]}] =
             reply["result"]["structuredContent"]["things"]

    {reply, state} = call(state, "read_property", %{"thing_id" => id, "property" => "temperature"})
    assert %{"value" => 20.5, "status" => "ok"} = reply["result"]["structuredContent"]
    {reply, _state} = call(state, "read_property", %{"thing_id" => id, "property" => "missing"})

    assert reply["result"]["isError"] and
             reply["result"]["structuredContent"]["error"]["code"] != nil
  end

  test "writes need the host token, one idempotency key per request and a bounded deadline" do
    lab = start_supervised!({Lab, id: "mcp-writes", max_children: 4})
    {id, thing} = start_thing(lab)

    credentials =
      {StaticRef, %{references: %{"bearer_sc" => "ref"}, lookup: fn "ref" -> {:ok, "t"} end}}

    state = session(instance: lab, writes: true, write_token: @token, credentials: credentials)
    {reply, _} = Server.handle(state, request(2, "tools/list"))
    assert "invoke_action" in Enum.map(reply["result"]["tools"], & &1["name"])

    args = %{
      "thing_id" => id,
      "action" => "setTarget",
      "input" => 22.0,
      "authorization" => @token,
      "idempotency_key" => "k-1"
    }

    {reply, state} = call(state, "invoke_action", args)
    assert %{"status" => "accepted"} = reply["result"]["structuredContent"]
    assert %{handler_calls: 1} = Thing.stats(thing)

    {reply, state} = call(state, "invoke_action", args)
    assert reply["error"]["code"] == -32_001 and reply["error"]["message"] =~ "already used"

    {reply, state} =
      call(state, "invoke_action", %{args | "authorization" => "wrong", "idempotency_key" => "k-2"})

    assert reply["error"]["message"] == "authorization refused"
    {reply, state} = call(state, "invoke_action", %{args | "idempotency_key" => ""})
    assert reply["error"]["code"] == -32_602

    {reply, state} =
      call(
        state,
        "invoke_action",
        Map.merge(args, %{"idempotency_key" => "k-3", "deadline_ms" => 999_999})
      )

    assert reply["error"]["code"] == -32_602

    {reply, state} =
      call(state, "invoke_action", Map.merge(args, %{"idempotency_key" => "k-4", "input" => 99.0}))

    assert reply["result"]["isError"]

    {reply, _state} =
      call(
        state,
        "invoke_action",
        Map.merge(args, %{"idempotency_key" => "k-5", "thing_id" => "urn:other"})
      )

    assert reply["error"]["code"] == -32_002
    assert %{handler_calls: 1} = Thing.stats(thing)
  end

  test "session quotas bound calls and output" do
    state = session(max_calls: 2)
    {reply, state} = call(state, "explain_seam", %{"seam" => "supervision"})
    assert reply["result"]
    {reply, state} = call(state, "explain_seam", %{"seam" => "supervision"})
    assert reply["result"]
    {reply, _} = call(state, "explain_seam", %{"seam" => "supervision"})
    assert reply["error"]["message"] =~ "call quota"

    state = session(max_output_bytes: 64)
    {reply, _} = call(state, "explain_seam", %{"seam" => "supervision"})
    assert reply["error"]["message"] =~ "output quota"
    {reply, _} = Server.handle(state, request(9, "resources/read", %{"uri" => "wotex-lab://seams"}))
    assert reply["error"]["message"] =~ "output quota"
    assert Tools.list(state) |> length() == 8
  end

  test "the stdio transport answers line by line and survives bad lines" do
    {:ok, state} = Server.new()

    lines = [
      Jason.encode!(request(1, "initialize", %{"protocolVersion" => "2025-11-25"})),
      "",
      "not json",
      Jason.encode!(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}),
      Jason.encode!(
        request(2, "tools/call", %{
          "name" => "explain_seam",
          "arguments" => %{"seam" => "reconnect"}
        })
      ),
      String.duplicate("x", 300)
    ]

    {:ok, input} = StringIO.open(Enum.join(lines, "\n") <> "\n")
    {:ok, output} = StringIO.open("")
    final = Stdio.run(state, input, output, max_line_bytes: 256)
    assert final.calls == 1 and final.initialized
    {_in, written} = StringIO.contents(output)
    replies = written |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    assert [
             %{"id" => 1, "result" => _},
             %{"id" => nil, "error" => %{"code" => -32_700}},
             %{"id" => 2, "result" => _},
             %{"id" => nil, "error" => %{"code" => -32_700, "message" => "line exceeds 256 bytes"}}
           ] = replies

    refute written =~ "Warning"
  end

  test "the streamable HTTP transport enforces origin, sessions, body size and methods" do
    {:ok, base} = Server.new()
    sessions = MCPPlug.sessions_table()

    config =
      MCPPlug.init(
        server: base,
        origins: ["http://localhost:4000"],
        sessions: sessions,
        max_body_bytes: 2_048
      )

    post = fn body, headers, cfg ->
      conn = Plug.Test.conn(:post, "/mcp", body)
      conn = Enum.reduce(headers, conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
      MCPPlug.call(conn, cfg)
    end

    init_body = Jason.encode!(request(1, "initialize", %{"protocolVersion" => "2025-11-25"}))
    conn = post.(init_body, [{"origin", "http://localhost:4000"}], config)
    assert conn.status == 200
    [session_id] = Plug.Conn.get_resp_header(conn, "mcp-session-id")
    assert Jason.decode!(conn.resp_body)["result"]["serverInfo"]["name"] == "wotex_lab"

    conn = post.(Jason.encode!(request(2, "ping")), [{"mcp-session-id", session_id}], config)
    assert conn.status == 200 and Jason.decode!(conn.resp_body)["result"] == %{}

    conn =
      post.(
        Jason.encode!(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}),
        [{"mcp-session-id", session_id}],
        config
      )

    assert conn.status == 202
    assert post.(Jason.encode!(request(3, "ping")), [], config).status == 404

    assert post.(
             Jason.encode!(request(3, "ping")),
             [{"origin", "http://evil.example"}, {"mcp-session-id", session_id}],
             config
           ).status == 403

    conn = post.("{", [{"mcp-session-id", session_id}], config)
    assert conn.status == 400 and Jason.decode!(conn.resp_body)["error"]["code"] == -32_700

    assert post.(String.duplicate("x", 4_096), [{"mcp-session-id", session_id}], config).status ==
             413

    assert MCPPlug.call(Plug.Test.conn(:get, "/mcp"), config).status == 405

    delete = fn headers, cfg ->
      conn =
        Enum.reduce(headers, Plug.Test.conn(:delete, "/mcp"), fn {k, v}, c ->
          Plug.Conn.put_req_header(c, k, v)
        end)

      MCPPlug.call(conn, cfg)
    end

    assert delete.([{"origin", "http://evil.example"}], config).status == 403
    assert delete.([], config).status == 400
    assert delete.([{"mcp-session-id", session_id}], config).status == 204

    assert post.(Jason.encode!(request(4, "ping")), [{"mcp-session-id", session_id}], config).status ==
             404

    expired = MCPPlug.init(server: base, sessions: sessions, session_ttl_ms: 1)
    conn = post.(init_body, [], expired)
    [old] = Plug.Conn.get_resp_header(conn, "mcp-session-id")
    Process.sleep(5)

    assert post.(Jason.encode!(request(5, "ping")), [{"mcp-session-id", old}], expired).status ==
             404

    _ = post.(init_body, [], expired)
    assert :ets.lookup(sessions, old) == []
  end
end
