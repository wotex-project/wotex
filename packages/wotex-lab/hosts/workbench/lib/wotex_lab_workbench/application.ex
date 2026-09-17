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
  `metrics_query` adds a separate loopback operator query listener; it needs
  local history and a credential different from the scrape credential.
  BeamLens additionally requires explicit activation plus local history, and
  starts only its bounded trusted-operator skill/provider bridge processes.
  A `control_mutations` limit list, instead of the default `false`, adds
  `WotexLabWorkbench.Control.Limits` before the endpoint so the HTTP control
  API admits its opted-in mutations; invalid limits refuse application start.
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
       max_sessions: Keyword.fetch!(env, :max_sessions)}
    ]

    with {:ok, observability} <- observability(env),
         {:ok, control} <- control(Keyword.get(env, :control_mutations, false)) do
      Supervisor.start_link(observability ++ children ++ control ++ [WotexLabWorkbenchWeb.Endpoint],
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
    query = Keyword.fetch!(env, :metrics_query)

    with :ok <- observability_requirements(promex?, history?, scrape, durable, beamlens?),
         :ok <- query_requirements(history?, scrape, query),
         do: observability_children(promex?, history?, scrape, durable, beamlens?, env)
  end

  defp observability_children(false, _history, _scrape, _durable, _beamlens, _env), do: {:ok, []}

  defp observability_children(true, history?, scrape, durable, beamlens?, env) do
    history = if history?, do: Keyword.fetch!(env, :metrics_history_options), else: false

    with {:ok, beamlens} <- beamlens_options(beamlens?) do
      {:ok,
       [
         {WotexLabWorkbench.Observability.Supervisor,
          history: history,
          scrape: scrape,
          durable: durable,
          beamlens: beamlens,
          query: Keyword.fetch!(env, :metrics_query)}
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

  defp query_requirements(_, _, false), do: :ok
  defp query_requirements(false, _, _), do: {:error, :metrics_query_requires_history}

  defp query_requirements(true, scrape, query) do
    if scrape != false and scrape[:token_digest] == query[:token_digest],
      do: {:error, :metrics_query_requires_distinct_credential},
      else: :ok
  end

  defp control(false), do: {:ok, []}

  defp control(limits) do
    with {:ok, options} <- WotexLabWorkbench.Control.Limits.configure(limits),
         do: {:ok, [{WotexLabWorkbench.Control.Limits, options}]}
  end

  defp beamlens_options(false), do: {:ok, false}
  defp beamlens_options(true), do: InvestigationConfig.client_registry()

  @impl Application
  def config_change(changed, _new, removed) do
    WotexLabWorkbenchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
