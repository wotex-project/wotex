defmodule WotexLabWorkbench.Investigation.Provider do
  @moduledoc """
  Explicit BeamLens provider selection: ChatGPT-plan Codex first, then a fixed
  local Ollama model.

  Missing login, API-key authentication, unavailable quota, timeout or an
  app-server failure causes a visible local fallback. The caller supplies a
  whole-request deadline; this module never discovers API keys or downloads a
  model.
  """

  alias WotexLabWorkbench.Investigation.{CodexRunner, Deadline, Ollama, Status}

  @app :wotex_lab_workbench
  @topic "wotex-lab:investigation-provider"

  @doc "PubSub topic carrying provider state changes."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Last disclosed provider state."
  @spec status() :: map()
  def status, do: Status.get()

  @doc false
  @spec reset() :: :ok
  def reset, do: Status.reset()

  @doc "Completes through Codex plan access, falling back visibly to local Ollama."
  @spec complete([map()], keyword()) :: {:ok, String.t(), map()} | {:error, atom()}
  def complete(messages, opts \\ []) when is_list(messages) do
    started_at = now()
    deadline = started_at + Keyword.get(opts, :timeout, 29_000)
    publish(%{state: :running, provider: :codex, model: nil, reason: nil})

    codex_timeout = min(config!(:beamlens_codex_timeout_ms), div(max(deadline - started_at, 0), 2))

    codex_opts =
      opts
      |> Keyword.put(:timeout, codex_timeout)
      |> Keyword.put_new(:model, config!(:beamlens_codex_model))

    case bounded_complete(codex_runner(), messages, codex_opts) do
      {:ok, content, metadata} ->
        finish(:ok, content, metadata, nil, started_at)

      {:error, codex_reason} ->
        publish(%{
          state: :fallback,
          provider: :ollama,
          model: config!(:beamlens_ollama_model),
          reason: reason_label(codex_reason)
        })

        remaining = max(deadline - now(), 0)

        case bounded_complete(ollama_runner(), messages, Keyword.put(opts, :timeout, remaining)) do
          {:ok, content, metadata} ->
            finish(:ok, content, metadata, codex_reason, started_at)

          {:error, ollama_reason} ->
            finish(
              :error,
              nil,
              %{provider: nil, model: nil},
              {codex_reason, ollama_reason},
              started_at
            )
        end
    end
  end

  @doc "Checks both configured reasoners without consuming a model turn."
  @spec preflight() :: %{codex: term(), ollama: term(), available: boolean()}
  def preflight do
    codex = bounded_preflight(codex_runner(), 5_000)
    ollama = bounded_preflight(ollama_runner(), 2_000)
    %{codex: codex, ollama: ollama, available: match?({:ok, _}, codex) or match?({:ok, _}, ollama)}
  end

  @doc "Checks availability and publishes the selected provider or failure."
  @spec refresh_status() :: map()
  def refresh_status do
    availability = preflight()
    publish(availability_status(availability))
    availability
  end

  defp bounded_complete(runner, messages, opts) do
    case Deadline.run(fn -> runner.complete(messages, opts) end, opts[:timeout]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp bounded_preflight(runner, timeout) do
    case Deadline.run(fn -> runner.preflight() end, timeout) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish(:ok, content, metadata, fallback_reason, started_at) do
    status = %{
      state: :ready,
      provider: metadata.provider,
      model: metadata.model,
      reason: if(fallback_reason, do: reason_label(fallback_reason)),
      plan_type: metadata[:plan_type],
      quota: metadata[:quota],
      usage: metadata[:usage],
      elapsed_ms: max(now() - started_at, 0),
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    publish(status)
    emit(status, :ok)
    {:ok, content, status}
  end

  defp finish(:error, _content, _metadata, reason, started_at) do
    status = %{
      state: :unavailable,
      provider: nil,
      model: nil,
      reason: reason_label(reason),
      elapsed_ms: max(now() - started_at, 0),
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    publish(status)
    emit(status, :error)
    {:error, :diagnostics_unavailable}
  end

  defp availability_status(%{codex: {:ok, metadata}}) do
    %{
      state: :available,
      provider: :codex,
      model: nil,
      reason: nil,
      plan_type: metadata[:plan_type],
      quota: metadata[:quota]
    }
  end

  defp availability_status(%{codex: {:error, codex_reason}, ollama: {:ok, metadata}}) do
    %{
      state: :available,
      provider: :ollama,
      model: metadata[:model] || config!(:beamlens_ollama_model),
      reason: reason_label(codex_reason)
    }
  end

  defp availability_status(%{codex: {:error, codex_reason}, ollama: {:error, ollama_reason}}) do
    %{
      state: :unavailable,
      provider: nil,
      model: nil,
      reason: reason_label({codex_reason, ollama_reason})
    }
  end

  defp emit(status, result) do
    :telemetry.execute(
      [:wotex, :lab, :investigation, :completion],
      %{duration_ms: status.elapsed_ms},
      %{
        provider: status.provider,
        model: status.model,
        result: result,
        fallback: status.reason != nil
      }
    )
  end

  defp publish(status) do
    status = status |> Map.put_new(:completed_at, nil) |> Map.put(:request_id, inspect(self()))
    Status.put(status)
    Phoenix.PubSub.broadcast(WotexLabWorkbench.PubSub, @topic, {:investigation_provider, status})
    :ok
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp reason_label({codex, ollama}),
    do: "Codex: #{reason_label(codex)}; Ollama: #{reason_label(ollama)}"

  defp reason_label(:api_key_auth_refused),
    do: "API-key auth refused; ChatGPT plan login is required"

  defp reason_label(:chatgpt_login_required), do: "ChatGPT login required"
  defp reason_label(:chatgpt_plan_quota_unavailable), do: "ChatGPT plan quota unavailable"
  defp reason_label(:codex_not_installed), do: "Codex CLI not installed"
  defp reason_label(:codex_timeout), do: "Codex timed out"
  defp reason_label(:timeout), do: "provider timed out"
  defp reason_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_label(reason), do: inspect(reason, limit: 5, printable_limit: 300)

  defp codex_runner,
    do: Application.get_env(@app, :beamlens_codex_runner, CodexRunner)

  defp ollama_runner,
    do: Application.get_env(@app, :beamlens_ollama_runner, Ollama)

  defp config!(key), do: Application.fetch_env!(@app, key)
  defp now, do: System.monotonic_time(:millisecond)
end
