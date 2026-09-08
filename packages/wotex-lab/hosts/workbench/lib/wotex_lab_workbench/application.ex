defmodule WotexLabWorkbench.Application do
  @moduledoc """
  Explicit supervision for the workbench host.

  Children in order: PubSub, one named `Wotex.Lab` instance, the bounded
  telemetry ring, the optional formal profile (only when the operator
  configured an engine), the session registry and the endpoint. Nothing else
  starts implicitly and no child starts an experiment. Explicit `promex_enabled`
  configuration prepends the host-owned custom metric collector/relay supervisor.
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

    children =
      if Keyword.fetch!(env, :promex_enabled),
        do: [WotexLabWorkbench.Observability.Supervisor | children],
        else: children

    Supervisor.start_link(children, strategy: :one_for_one, name: WotexLabWorkbench.Supervisor)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    WotexLabWorkbenchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
