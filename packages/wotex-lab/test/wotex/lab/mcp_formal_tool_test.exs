defmodule Wotex.Lab.MCPFormalToolTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.MCP.Server

  test "a configured but unavailable formal profile reports unsupported, and closed inputs are enforced" do
    formal = [
      pool: :mcp_formal_missing,
      binary: "/nonexistent/maude",
      binary_digest: "sha256:" <> String.duplicate("0", 64)
    ]

    {:ok, state} = Server.new(formal: formal)

    call = fn args ->
      Server.handle(state, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "verify_control_model", "arguments" => args}
      })
    end

    {reply, _} = call.(%{"variant" => "safe", "property" => "no_stale_dispatch"})

    assert %{"status" => "unsupported", "reason" => "unsupported"} =
             reply["result"]["structuredContent"]

    {reply, _} = call.(%{"variant" => "teleport", "property" => "no_stale_dispatch"})

    assert reply["error"]["code"] == -32_602 and
             reply["error"]["message"] =~ "variant must be one of"

    {reply, _} = call.(%{"variant" => "safe", "property" => "search [1] in X : a =>* b ."})

    assert reply["error"]["code"] == -32_602 and
             reply["error"]["message"] =~ "property must be one of"

    {reply, _} = call.(%{"variant" => 1})
    assert reply["error"]["code"] == -32_602
  end
end
