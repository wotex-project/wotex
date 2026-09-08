defmodule WotexLabWorkbench.Application do
  @moduledoc """
  Explicit supervision for the workbench host.

  Children in order: PubSub, one named `Wotex.Lab` instance, the bounded
  telemetry ring, the optional formal profile (only when the operator
  configured an engine), the session registry and the endpoint. Nothing else
  starts implicitly and no child starts an experiment. Explicit `promex_enabled`
  configuration prepends the host-owned custom metric collector/relay supervisor.
  Separate `metrics_history_enabled` activation adds bounded operator history
  and a self-sampler, and is refused unless PromEx is also explicitly enabled.
  `metrics_scrape` separately admits a credential-protected loopback listener;
  it also requires explicit PromEx activation and never joins browser routing.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    env = Application.get_all_env(:wotex_lab_workbench)
    lab = WotexLabWorkbench.lab()

    children = [
      {Phoenix.PubSub, name: WotexLabWorkbench.PubSub},
      Wotex.Lab.child_spec(
        id: "workbench",
        name: lab,
        max_children: Keyword.fetch!(env, :lab_max_children)
      ),
      {WotexLabWorkbench.Metrics, capacity: Keyword.fetch!(env, :metrics_capacity)},
      {WotexLabWorkbench.Formal, lab: lab, engine: Keyword.get(env, :formal_engine)},
      {WotexLabWorkbench.Sessions,
       lab: lab,
       ttl_ms: Keyword.fetch!(env, :session_ttl_ms),
       sweep_ms: Keyword.fetch!(env, :session_sweep_ms),
       max_sessions: Keyword.fetch!(env, :max_sessions)},
      WotexLabWorkbenchWeb.Endpoint
    ]

    with {:ok, observability} <- observability(env) do
      Supervisor.start_link(observability ++ children,
        strategy: :one_for_one,
        name: WotexLabWorkbench.Supervisor
      )
    end
  end

  defp observability(env) do
    case {Keyword.fetch!(env, :promex_enabled), Keyword.fetch!(env, :metrics_history_enabled),
          Keyword.fetch!(env, :metrics_scrape)} do
      {false, true, _scrape} ->
        {:error, :metrics_history_requires_promex}

      {false, false, false} ->
        {:ok, []}

      {false, false, _scrape} ->
        {:error, :metrics_scrape_requires_promex}

      {true, history?, scrape} ->
        history = if history?, do: Keyword.fetch!(env, :metrics_history_options), else: false
        {:ok, [{WotexLabWorkbench.Observability.Supervisor, history: history, scrape: scrape}]}
    end
  end

  @impl Application
  def config_change(changed, _new, removed) do
    WotexLabWorkbenchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
