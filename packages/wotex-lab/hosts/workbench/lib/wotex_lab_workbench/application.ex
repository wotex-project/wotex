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
  `metrics_durable` adds the bounded local or explicitly pinned hosted
  GreptimeDB exporter and replaces the sampler as the writer when local
  history is also active.
  `metrics_scrape` separately admits a credential-protected loopback listener;
  it also requires explicit PromEx activation and never joins browser routing.
  BeamLens additionally requires explicit activation plus local history, and
  starts only its bounded trusted-operator skill/provider bridge processes.
  """

  use Application

  alias WotexLabWorkbench.Investigation.Config, as: InvestigationConfig

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
    promex? = Keyword.fetch!(env, :promex_enabled)
    history? = Keyword.fetch!(env, :metrics_history_enabled)
    scrape = Keyword.fetch!(env, :metrics_scrape)
    durable = Keyword.fetch!(env, :metrics_durable)
    beamlens? = Keyword.fetch!(env, :beamlens_enabled)

    with :ok <- observability_requirements(promex?, history?, scrape, durable, beamlens?),
         do: observability_children(promex?, history?, scrape, durable, beamlens?, env)
  end

  defp observability_children(false, _history, _scrape, _durable, _beamlens, _env), do: {:ok, []}

  defp observability_children(true, history?, scrape, durable, beamlens?, env) do
    history = if history?, do: Keyword.fetch!(env, :metrics_history_options), else: false

    with {:ok, beamlens} <- beamlens_options(beamlens?) do
      {:ok,
       [
         {WotexLabWorkbench.Observability.Supervisor,
          history: history, scrape: scrape, durable: durable, beamlens: beamlens}
       ]}
    end
  end

  defp observability_requirements(false, true, _scrape, _durable, _beamlens),
    do: {:error, :metrics_history_requires_promex}

  defp observability_requirements(_promex, false, _scrape, _durable, true),
    do: {:error, :beamlens_requires_metrics_history}

  defp observability_requirements(false, false, scrape, false, false) when scrape != false,
    do: {:error, :metrics_scrape_requires_promex}

  defp observability_requirements(false, false, false, durable, false) when durable != false,
    do: {:error, :metrics_durable_requires_promex}

  defp observability_requirements(_promex, _history, _scrape, _durable, _beamlens), do: :ok

  defp beamlens_options(false), do: {:ok, false}
  defp beamlens_options(true), do: InvestigationConfig.client_registry()

  @impl Application
  def config_change(changed, _new, removed) do
    WotexLabWorkbenchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
