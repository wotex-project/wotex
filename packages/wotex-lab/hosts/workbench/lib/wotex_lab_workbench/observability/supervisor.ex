defmodule WotexLabWorkbench.Observability.Supervisor do
  @moduledoc """
  Explicit host-owned PromEx activation. No public listener, database, polling
  of application internals or model service starts here. The normalized relay
  follows the collector in a one-for-all lifecycle; neither can outlive its host.
  Optional local history shares that lifecycle: a restart discards the whole
  volatile cohort, not just its sampler. Browser sessions cannot activate it.
  `:scrape` separately admits an authenticated loopback-only operator listener.
  `:durable` adds one bounded local or explicitly pinned hosted GreptimeDB
  exporter; when history is also active that exporter is its sole writer, so
  no capture is duplicated. `:durable_query` admits
  `WotexLabWorkbench.Observability.DurableReader` options, so inspection scopes
  can also read the configured durable receiver. `:query` adds the loopback operator
  query listener after the history cohort; it needs history or durable reads
  and a credential distinct from `:scrape`.
  `:hosted` adds the digest-only tenant registry, TLS listener and isolated
  investigation broker. It requires durable reads and never exposes the
  host-wide volatile history.
  """

  use Supervisor

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.History

  alias WotexLabWorkbench.Investigation.{
    BeamlensSupervisor,
    Broker,
    ContextStore,
    Status
  }

  alias WotexLabWorkbench.Observability.{
    Durable,
    DurableReader,
    HostedAccess,
    HostedListener,
    Inspection,
    PromEx,
    QueryListener,
    Relay,
    Sampler,
    Scrape
  }

  @doc "Starts capture/relay; explicit options add bounded history, scrape and BeamLens surfaces."
  @spec start_link(keyword()) :: Supervisor.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <-
           Options.validate(opts, [
             :history,
             :scrape,
             :durable,
             :durable_query,
             :beamlens,
             :query,
             :hosted
           ]),
         :ok <- history_options(Keyword.get(opts, :history, false)),
         :ok <- scrape_options(Keyword.get(opts, :scrape, false)),
         :ok <- durable_options(Keyword.get(opts, :durable, false)),
         :ok <- durable_query_options(Keyword.get(opts, :durable_query, false)),
         :ok <- beamlens_options(Keyword.get(opts, :beamlens, false)),
         :ok <- query_options(Keyword.get(opts, :query, false)),
         :ok <- hosted_options(Keyword.get(opts, :hosted, false)),
         :ok <-
           hosted_dependencies(
             Keyword.get(opts, :durable_query, false),
             Keyword.get(opts, :hosted, false)
           ),
         :ok <-
           query_dependencies(
             Keyword.get(opts, :history, false) != false or
               Keyword.get(opts, :durable_query, false) != false,
             Keyword.get(opts, :scrape, false),
             Keyword.get(opts, :query, false)
           ),
         :ok <-
           dependencies(Keyword.get(opts, :history, false), Keyword.get(opts, :beamlens, false)),
         do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    history = Keyword.get(opts, :history, false)
    durable = Keyword.get(opts, :durable, false)

    children =
      [PromEx, {Relay, []}] ++
        history_children(history, durable) ++
        inspection_children(history, Keyword.get(opts, :durable_query, false)) ++
        durable_children(durable, history) ++
        scrape_children(Keyword.get(opts, :scrape, false)) ++
        query_children(Keyword.get(opts, :query, false)) ++
        hosted_children(
          Keyword.get(opts, :hosted, false),
          Keyword.get(opts, :durable_query, false)
        ) ++
        beamlens_children(Keyword.get(opts, :beamlens, false))

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp history_options(false), do: :ok

  defp history_options(opts),
    do: Options.validate(opts, [:interval_ms, :max_snapshots, :max_bytes, :max_queries])

  defp scrape_options(false), do: :ok
  defp scrape_options(opts), do: Scrape.validate(opts)

  defp durable_options(false), do: :ok
  defp durable_options(opts), do: Durable.validate(opts)

  defp durable_query_options(false), do: :ok
  defp durable_query_options(opts), do: DurableReader.validate(opts)

  defp beamlens_options(false), do: :ok

  defp beamlens_options(%{
         capability: capability,
         registry: %{primary: primary, clients: clients}
       })
       when is_binary(capability) and byte_size(capability) in 43..128 and
              is_binary(primary) and is_list(clients) and clients != [],
       do: :ok

  defp beamlens_options(_),
    do: {:error, Error.new(:invalid_beamlens, :construction, "BeamLens options are invalid")}

  defp dependencies(false, beamlens) when beamlens != false,
    do:
      {:error, Error.new(:beamlens_requires_history, :construction, "BeamLens needs local history")}

  defp dependencies(_, _), do: :ok

  defp query_options(false), do: :ok
  defp query_options(opts), do: QueryListener.validate(opts)

  defp hosted_options(false), do: :ok

  defp hosted_options(opts) do
    with :ok <- Options.validate(opts, [:tenants, :listener, :command, :provider]),
         tenants when is_list(tenants) and tenants != [] <- Keyword.get(opts, :tenants),
         :ok <- HostedListener.validate(Keyword.get(opts, :listener, [])),
         {:ok, _} <-
           WotexLabWorkbench.Investigation.HostedCommand.configure(Keyword.get(opts, :command, [])),
         provider when provider in [:codex_then_ollama, :ollama] <- Keyword.get(opts, :provider) do
      :ok
    else
      {:error, _} = error ->
        error

      _ ->
        {:error,
         Error.new(:invalid_hosted_access, :construction, "hosted access options are invalid")}
    end
  end

  defp hosted_dependencies(_, false), do: :ok

  defp hosted_dependencies(false, _),
    do:
      {:error,
       Error.new(
         :hosted_access_requires_durable_query,
         :construction,
         "hosted access needs durable reads"
       )}

  defp hosted_dependencies(_, _), do: :ok

  defp query_dependencies(_, _, false), do: :ok

  defp query_dependencies(false, _, _),
    do:
      {:error,
       Error.new(
         :metrics_query_requires_history,
         :construction,
         "metric queries need local history or durable reads"
       )}

  defp query_dependencies(_, scrape, query) do
    if scrape != false and scrape[:token_digest] == query[:token_digest],
      do:
        {:error,
         Error.new(
           :metrics_query_requires_distinct_credential,
           :construction,
           "the query credential must differ from the scrape credential"
         )},
      else: :ok
  end

  defp query_children(false), do: []
  defp query_children(opts), do: [{QueryListener, opts}]

  defp hosted_children(false, _), do: []

  defp hosted_children(opts, durable) do
    [
      {Task.Supervisor, name: WotexLabHosted.TaskSupervisor},
      {HostedAccess, tenants: opts[:tenants], durable: durable},
      {WotexLabWorkbench.Investigation.HostedBroker,
       command: opts[:command], provider: opts[:provider]},
      {HostedListener, opts[:listener]}
    ]
  end

  defp scrape_children(false), do: []
  defp scrape_children(opts), do: [{Scrape, opts}]

  defp beamlens_children(false), do: []

  defp beamlens_children(%{capability: capability, registry: registry}) do
    [
      Status,
      ContextStore,
      {BeamlensSupervisor, client_registry: registry},
      {Broker, bridge_capability: capability}
    ]
  end

  defp history_children(false, _), do: []

  defp history_children(opts, durable) do
    history =
      Keyword.take(opts, [:max_snapshots, :max_bytes, :max_queries]) ++
        [id: :operator, name: __MODULE__.History, instance: "workbench", instance_slot: 0]

    sampler = {Sampler, [history: __MODULE__.History] ++ Keyword.take(opts, [:interval_ms])}

    if durable == false,
      do: [{History, history}, sampler],
      else: [{History, history}]
  end

  defp inspection_children(false, false), do: []

  defp inspection_children(history, durable_query) do
    sources =
      if(history == false, do: [], else: [history: __MODULE__.History]) ++
        if durable_query == false, do: [], else: [durable: durable_query]

    [{Inspection, sources}]
  end

  defp durable_children(false, _), do: []

  defp durable_children(opts, history) do
    history = if history == false, do: nil, else: __MODULE__.History
    [{Wotex.Lab.Metrics.GreptimeBridge, Durable.child_options(opts, history)}]
  end
end
