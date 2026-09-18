defmodule WotexLabWorkbench.Investigation.CodexRunner do
  @moduledoc """
  Minimal Codex App Server client for one ephemeral diagnostic completion.

  It does not read token files or API keys. Authentication and quota are read
  through the app-server protocol, and only an existing ChatGPT-plan account is
  accepted. Every call owns and closes its stdio port and private empty working
  directory.
  """

  @default_timeout 18_000
  @max_line_bytes 4_194_304

  @doc "Runs one turn after proving ChatGPT-plan authentication and available quota."
  @spec complete([map()], keyword()) :: {:ok, String.t(), map()} | {:error, term()}
  def complete(messages, opts \\ []) when is_list(messages) do
    with codex when is_binary(codex) <- executable(opts),
         {:ok, working_directory} <- diagnostic_directory() do
      try do
        run(codex, working_directory, messages, opts)
      after
        :file.del_dir(String.to_charlist(working_directory))
      end
    else
      nil -> {:error, :codex_not_installed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Checks ChatGPT auth and plan quota without starting a model turn."
  @spec preflight(keyword()) :: {:ok, map()} | {:error, term()}
  def preflight(opts \\ []) do
    case executable(opts) do
      nil ->
        {:error, :codex_not_installed}

      codex ->
        deadline = now() + Keyword.get(opts, :timeout, 5_000)
        port = open_port(codex)

        try do
          with {:ok, _} <- request(port, 1, "initialize", initialize_params(), deadline),
               :ok <- notify(port, "initialized", %{}),
               {:ok, account_result} <-
                 request(port, 2, "account/read", %{refreshToken: false}, deadline),
               {:ok, account} <- authorize_account(account_result),
               {:ok, rate_result} <- request(port, 3, "account/rateLimits/read", %{}, deadline),
               {:ok, quota} <- authorize_quota(rate_result) do
            {:ok, Map.merge(account, %{quota: quota})}
          end
        after
          if Port.info(port), do: Port.close(port)
        end
    end
  rescue
    _ -> {:error, :invalid_codex_response}
  catch
    :exit, reason -> {:error, {:codex_port_exit, sanitize(reason)}}
  end

  defp run(codex, working_directory, messages, opts) do
    deadline = now() + Keyword.get(opts, :timeout, @default_timeout)
    port = open_port(codex)

    try do
      with {:ok, _} <- request(port, 1, "initialize", initialize_params(), deadline),
           :ok <- notify(port, "initialized", %{}),
           {:ok, account_result} <-
             request(port, 2, "account/read", %{refreshToken: false}, deadline),
           {:ok, account} <- authorize_account(account_result),
           {:ok, rate_result} <- request(port, 3, "account/rateLimits/read", %{}, deadline),
           {:ok, quota} <- authorize_quota(rate_result),
           {:ok, config_result} <-
             request(
               port,
               7,
               "config/read",
               %{includeLayers: false, cwd: working_directory},
               deadline
             ),
           {:ok, restrictions} <- disabled_integrations(config_result),
           {:ok, thread_result} <-
             request(
               port,
               4,
               "thread/start",
               thread_params(working_directory, Keyword.put(opts, :restrictions, restrictions)),
               deadline
             ),
           {:ok, thread_id, resolved_model} <- thread_identity(thread_result),
           {:ok, inventory} <-
             request(port, 6, "mcpServerStatus/list", %{threadId: thread_id}, deadline),
           :ok <- check_inventory(inventory),
           {:ok, _} <-
             request(port, 5, "turn/start", turn_params(thread_id, messages, opts), deadline),
           {:ok, content, usage} <- await_turn(port, thread_id, deadline) do
        {:ok, content,
         %{
           provider: :codex,
           model: resolved_model,
           plan_type: account.plan_type,
           quota: quota,
           usage: usage
         }}
      end
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    _ -> {:error, :invalid_codex_response}
  catch
    :exit, reason -> {:error, {:codex_port_exit, sanitize(reason)}}
  end

  defp disabled_integrations(%{"config" => config}) when is_map(config) do
    restrictions =
      Map.new(["mcp_servers", "plugins"], fn key ->
        entries = Map.get(config, key) || %{}
        {key, Map.new(entries, fn {name, _} -> {name, %{"enabled" => false}} end)}
      end)

    {:ok, restrictions}
  end

  defp disabled_integrations(_), do: {:error, :invalid_codex_config}

  defp check_inventory(%{"data" => entries} = inventory) when is_list(entries) do
    if is_nil(inventory["nextCursor"]) and Enum.all?(entries, &empty_capabilities?/1),
      do: :ok,
      else: {:error, :diagnostic_tools_available}
  end

  defp check_inventory(_), do: {:error, :invalid_codex_inventory}

  defp empty_capabilities?(%{"tools" => tools, "resources" => [], "resourceTemplates" => []}),
    do: tools == %{}

  defp empty_capabilities?(_), do: false

  defp initialize_params do
    %{
      clientInfo: %{name: "wotex-lab", title: "WoTEx Lab Investigation", version: "0.1.0"},
      capabilities: %{experimentalApi: false}
    }
  end

  defp open_port(codex) do
    Port.open({:spawn_executable, codex}, [
      :binary,
      :exit_status,
      {:line, @max_line_bytes},
      {:args, launch_args()}
    ])
  end

  @doc "Process-local restrictions; the user's Codex configuration is not mutated."
  @spec launch_args() :: [String.t()]
  def launch_args do
    disabled =
      ~w(shell_tool unified_exec apps browser_use browser_use_external computer_use image_generation code_mode code_mode_host multi_agent memories hooks goals remote_plugin skill_mcp_dependency_install)

    ["app-server", "--listen", "stdio://"] ++
      Enum.flat_map(disabled, &["--disable", &1]) ++
      Enum.flat_map(
        [
          "mcp_servers={}",
          "plugins={}",
          "web_search=\"disabled\"",
          "tools.view_image=false",
          "project_doc_max_bytes=0"
        ],
        &["-c", &1]
      )
  end

  defp thread_params(working_directory, opts) do
    %{
      cwd: working_directory,
      ephemeral: true,
      config: Keyword.fetch!(opts, :restrictions),
      sandbox: "read-only",
      approvalPolicy: "never",
      baseInstructions: """
      You are a read-only WoTEx Lab diagnostic reasoner. Use only the supplied
      evidence. Do not call tools, inspect files, access the network, or propose
      actions against physical equipment. Return only the requested response.
      """
    }
    |> maybe_put(:model, Keyword.get(opts, :model))
  end

  defp turn_params(thread_id, messages, opts) do
    %{
      threadId: thread_id,
      input: [%{type: "text", text: format_messages(messages), text_elements: []}],
      effort: "low",
      approvalPolicy: "never",
      sandboxPolicy: %{type: "readOnly", networkAccess: false}
    }
    |> maybe_put(:outputSchema, Keyword.get(opts, :output_schema))
  end

  defp request(port, id, method, params, deadline) do
    :ok = send_json(port, %{id: id, method: method, params: params})
    await_response(port, id, deadline)
  end

  defp notify(port, method, params), do: send_json(port, %{method: method, params: params})

  defp send_json(port, message) do
    true = Port.command(port, [Jason.encode!(message), "\n"])
    :ok
  end

  defp await_response(port, id, deadline) do
    with {:ok, message} <- next_message(port, deadline) do
      cond do
        message["id"] == id and is_map(message["result"]) ->
          {:ok, message["result"]}

        message["id"] == id and message["error"] ->
          {:error, {:codex_rpc, sanitize(message["error"])}}

        true ->
          await_response(port, id, deadline)
      end
    end
  end

  defp await_turn(port, thread_id, deadline, content \\ nil, usage \\ nil) do
    with {:ok, message} <- next_message(port, deadline) do
      params = message["params"] || %{}

      case turn_event(message, params, thread_id) do
        {:agent_message, text} ->
          await_turn(port, thread_id, deadline, text, usage)

        {:token_usage, token_usage} ->
          await_turn(port, thread_id, deadline, content, compact_usage(token_usage))

        {:completed, turn} ->
          complete_turn(turn, content, usage)

        :other ->
          await_turn(port, thread_id, deadline, content, usage)
      end
    end
  end

  defp turn_event(message, params, thread_id) do
    case {message["method"], params["threadId"] == thread_id} do
      {"item/completed", true} ->
        if get_in(params, ["item", "type"]) == "agentMessage",
          do: {:agent_message, get_in(params, ["item", "text"])},
          else: :other

      {"thread/tokenUsage/updated", true} ->
        {:token_usage, params["tokenUsage"]}

      {"turn/completed", true} ->
        {:completed, params["turn"] || %{}}

      _ ->
        :other
    end
  end

  defp complete_turn(turn, content, usage) do
    case {turn["status"], content || final_message(turn)} do
      {"completed", answer} when is_binary(answer) and answer != "" -> {:ok, answer, usage}
      _ -> {:error, {:codex_turn_failed, sanitize(turn["error"] || turn["status"])}}
    end
  end

  defp next_message(port, deadline) do
    remaining = max(deadline - now(), 0)

    receive do
      {^port, {:data, {:eol, line}}} -> decode_line(line)
      {^port, {:data, {:noeol, _}}} -> {:error, :codex_response_line_too_long}
      {^port, {:exit_status, status}} -> {:error, {:codex_exit_status, status}}
    after
      remaining -> {:error, :codex_timeout}
    end
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, message} when is_map(message) -> {:ok, message}
      _ -> {:error, :invalid_codex_response}
    end
  end

  @doc "Accepts ChatGPT-plan authentication and rejects API-key authentication."
  @spec authorize_account(map()) :: {:ok, map()} | {:error, atom()}
  def authorize_account(%{"account" => %{"type" => "chatgpt"} = account}),
    do: {:ok, %{plan_type: account["planType"] || "unknown"}}

  def authorize_account(%{"account" => %{"type" => "apiKey"}}),
    do: {:error, :api_key_auth_refused}

  def authorize_account(_), do: {:error, :chatgpt_login_required}

  @doc "Rejects exhausted or unavailable ChatGPT-plan quota."
  @spec authorize_quota(map()) :: {:ok, map()} | {:error, atom()}
  def authorize_quota(payload) when is_map(payload) do
    legacy = if is_map(payload["rateLimits"]), do: [payload["rateLimits"]], else: []

    buckets =
      if is_map(payload["rateLimitsByLimitId"]),
        do: Map.values(payload["rateLimitsByLimitId"]),
        else: []

    limits = legacy ++ buckets

    cond do
      limits == [] ->
        {:error, :rate_limits_unavailable}

      Enum.all?(limits, &available_limit?/1) ->
        primary = hd(limits)["primary"]
        {:ok, %{used_percent: primary["usedPercent"], resets_at: primary["resetsAt"]}}

      true ->
        {:error, :chatgpt_plan_quota_unavailable}
    end
  end

  def authorize_quota(_), do: {:error, :rate_limits_unavailable}

  defp available_limit?(%{"primary" => primary} = limit) do
    available_window?(primary) and
      (is_nil(limit["secondary"]) or available_window?(limit["secondary"])) and
      is_nil(limit["rateLimitReachedType"]) and limit["spendControlReached"] != true
  end

  defp available_limit?(_), do: false
  defp available_window?(%{"usedPercent" => used}), do: is_number(used) and used >= 0 and used < 100
  defp available_window?(_), do: false

  defp thread_identity(%{"thread" => %{"id" => thread_id}} = result),
    do: {:ok, thread_id, result["model"] || "codex-default"}

  defp thread_identity(_), do: {:error, :invalid_thread_response}

  defp format_messages(messages) do
    Enum.map_join(messages, "\n\n", fn message ->
      role = message["role"] || message[:role] || "user"
      content = message["content"] || message[:content] || ""
      "[#{role}]\n#{format_content(content)}"
    end)
  end

  defp format_content(content) when is_binary(content), do: content

  defp format_content(content) when is_list(content) do
    Enum.map_join(content, "\n", fn
      %{"text" => text} -> text
      %{text: text} -> text
      other -> Jason.encode!(other)
    end)
  end

  defp format_content(content), do: inspect(content, limit: 50, printable_limit: 10_000)

  defp final_message(%{"items" => items}) when is_list(items) do
    items
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "agentMessage", "text" => text} -> text
      _ -> nil
    end)
  end

  defp final_message(_), do: nil
  defp compact_usage(nil), do: nil

  defp compact_usage(usage) do
    total = usage["total"] || usage["last"] || %{}

    %{
      input_tokens: total["inputTokens"],
      cached_input_tokens: total["cachedInputTokens"],
      output_tokens: total["outputTokens"]
    }
  end

  defp diagnostic_directory do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    directory = Path.join(System.tmp_dir!(), "wotex-lab-investigation-empty-#{suffix}")

    case :file.make_dir(String.to_charlist(directory)) do
      :ok ->
        :ok = File.chmod(directory, 0o700)
        {:ok, directory}

      {:error, reason} ->
        {:error, {:diagnostic_directory, reason}}
    end
  end

  defp executable(opts), do: Keyword.get(opts, :executable) || System.find_executable("codex")
  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp sanitize(value) when is_atom(value) or is_number(value) or is_binary(value), do: value
  defp sanitize(value), do: inspect(value, limit: 10, printable_limit: 500)
  defp now, do: System.monotonic_time(:millisecond)
end
