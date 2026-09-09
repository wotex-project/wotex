defmodule Wotex.Lab.FormalMaudeMCPTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Formal.Profile
  alias Wotex.Lab.MCP.Server

  @moduletag :maude
  @moduletag timeout: 120_000

  test "the MCP tool runs the configured profile and returns model-scoped evidence" do
    binary = System.fetch_env!("WOTEX_LAB_MAUDE")
    {:ok, digest} = Digest.file(binary)
    lab = start_supervised!({Lab, id: "formal-mcp", max_children: 4})
    formal = [pool: :wotex_lab_formal_mcp, binary: binary, binary_digest: digest]
    {:ok, profile} = Profile.new(formal)
    {:ok, _} = Lab.start_child(lab, :sessions, Profile.child_spec(profile))
    {:ok, state} = Server.new(formal: formal)

    {reply, _} =
      Server.handle(state, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "verify_control_model",
          "arguments" => %{"variant" => "broken_both", "property" => "no_simultaneous_heat_cool"}
        }
      })

    assert %{
             "status" => "counterexample",
             "counterexample" => [_ | _],
             "model" => %{"module" => "BROKEN-BOTH"}
           } = reply["result"]["structuredContent"]
  end
end
