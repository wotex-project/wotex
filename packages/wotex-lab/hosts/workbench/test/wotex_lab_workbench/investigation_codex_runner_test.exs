defmodule WotexLabWorkbench.InvestigationCodexRunnerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias WotexLabWorkbench.Investigation.CodexRunner

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-lab-fake-codex-#{System.unique_integer([:positive, :monotonic])}"
      )

    script = Path.join(directory, "codex")
    File.mkdir!(directory)

    File.write!(script, """
    #!/bin/sh
    while IFS= read -r line; do
      case "$line" in
        *'"method":"initialize"'*)
          printf '%s\n' '{"id":1,"result":{"serverInfo":{"name":"fake"}}}'
          ;;
        *'"method":"account/read"'*)
          printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"pro"}}}'
          ;;
        *'"method":"account/rateLimits/read"'*)
          printf '%s\n' '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":12,"resetsAt":123},"rateLimitReachedType":null,"spendControlReached":false}}}'
          ;;
        *'"method":"config/read"'*)
          printf '%s\n' '{"id":7,"result":{"config":{"mcp_servers":{"example":{"enabled":true}},"plugins":{}}}}'
          ;;
        *'"method":"mcpServerStatus/list"'*)
          printf '%s\n' '{"id":6,"result":{"data":[]}}'
          ;;
        *'"method":"thread/start"'*)
          printf '%s\n' '{"id":4,"result":{"thread":{"id":"thread-1"},"model":"gpt-test"}}'
          ;;
        *'"method":"turn/start"'*)
          printf '%s\n' '{"id":5,"result":{"turn":{"id":"turn-1"}}}'
          printf '%s\n' '{"method":"item/completed","params":{"threadId":"thread-1","item":{"type":"agentMessage","text":"{\\"summary\\":\\"grounded\\"}"}}}'
          printf '%s\n' '{"method":"thread/tokenUsage/updated","params":{"threadId":"thread-1","tokenUsage":{"total":{"inputTokens":20,"cachedInputTokens":5,"outputTokens":7}}}}'
          printf '%s\n' '{"method":"turn/completed","params":{"threadId":"thread-1","turn":{"status":"completed"}}}'
          ;;
      esac
    done
    """)

    File.chmod!(script, 0o700)

    on_exit(fn ->
      File.rm(script)
      File.rmdir(directory)
    end)

    {:ok, executable: script}
  end

  test "launch disables execution, connectors, search and inherited integrations" do
    args = CodexRunner.launch_args()
    assert "shell_tool" in args
    assert "apps" in args
    assert "browser_use" in args
    assert "mcp_servers={}" in args
    assert "plugins={}" in args
    assert "web_search=\"disabled\"" in args
    assert "project_doc_max_bytes=0" in args
  end

  test "one ephemeral app-server turn returns bounded metadata", %{executable: script} do
    assert {:ok, ~s({"summary":"grounded"}), metadata} =
             CodexRunner.complete(
               [%{"role" => "user", "content" => "diagnose bounded evidence"}],
               executable: script,
               output_schema: %{"type" => "object"},
               timeout: 1_000
             )

    assert metadata.provider == :codex
    assert metadata.model == "gpt-test"
    assert metadata.plan_type == "pro"
    assert metadata.quota.used_percent == 12
    assert metadata.usage == %{input_tokens: 20, cached_input_tokens: 5, output_tokens: 7}
  end

  test "preflight reads plan auth and quota without a model turn", %{executable: script} do
    assert {:ok, %{plan_type: "pro", quota: %{used_percent: 12}}} =
             CodexRunner.preflight(executable: script, timeout: 1_000)
  end

  test "refuses any remaining MCP capability before a turn", %{executable: script} do
    contents =
      File.read!(script)
      |> String.replace(
        ~s({"data":[]}),
        ~s({"data":[{"tools":{"danger":{}},"resources":[],"resourceTemplates":[]}]})
      )

    File.write!(script, contents)

    assert {:error, :diagnostic_tools_available} =
             CodexRunner.complete([], executable: script, timeout: 1_000)
  end

  test "retains no account identity and refuses API-key billing" do
    assert {:ok, %{plan_type: "pro"}} =
             CodexRunner.authorize_account(%{
               "account" => %{
                 "type" => "chatgpt",
                 "planType" => "pro",
                 "email" => "private@example.test"
               }
             })

    assert {:error, :api_key_auth_refused} =
             CodexRunner.authorize_account(%{"account" => %{"type" => "apiKey"}})

    assert {:error, :chatgpt_login_required} = CodexRunner.authorize_account(%{})
  end

  test "quota must be present and available in every returned bucket" do
    assert {:error, :rate_limits_unavailable} = CodexRunner.authorize_quota(%{})

    assert {:error, :chatgpt_plan_quota_unavailable} =
             CodexRunner.authorize_quota(%{
               "rateLimits" => %{
                 "primary" => %{"usedPercent" => 100},
                 "rateLimitReachedType" => "primary"
               }
             })

    assert {:error, :chatgpt_plan_quota_unavailable} =
             CodexRunner.authorize_quota(%{
               "rateLimits" => %{"primary" => %{"usedPercent" => 10}},
               "rateLimitsByLimitId" => %{
                 "other" => %{"primary" => %{"usedPercent" => 100}}
               }
             })

    assert {:ok, %{used_percent: 28, resets_at: 123}} =
             CodexRunner.authorize_quota(%{
               "rateLimits" => %{
                 "primary" => %{"usedPercent" => 28, "resetsAt" => 123},
                 "rateLimitReachedType" => nil
               }
             })
  end
end
