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
           Options.validate(opts, [:history, :scrape, :durable, :durable_query, :beamlens, :query]),
         :ok <- history_options(Keyword.get(opts, :history, false)),
         :ok <- scrape_options(Keyword.get(opts, :scrape, false)),
         :ok <- durable_options(Keyword.get(opts, :durable, false)),
         :ok <- durable_query_options(Keyword.get(opts, :durable_query, false)),
         :ok <- beamlens_options(Keyword.get(opts, :beamlens, false)),
         :ok <- query_options(Keyword.get(opts, :query, false)),
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

  defp beamlens_options(_opts),
    do: {:error, Error.new(:invalid_beamlens, :construction, "BeamLens options are invalid")}

  defp dependencies(false, beamlens) when beamlens != false,
    do:
      {:error, Error.new(:beamlens_requires_history, :construction, "BeamLens needs local history")}

  defp dependencies(_history, _beamlens), do: :ok

  defp query_options(false), do: :ok
  defp query_options(opts), do: QueryListener.validate(opts)

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

  defp history_children(false, _durable), do: []

  defp history_children(opts, durable) do
    history =
      Keyword.take(opts, [:max_snapshots, :max_bytes, :max_queries]) ++
        [id: :operator, name: __MODULE__.History, instance: "workbench", instance_slot: 0]

    base = [{History, history}]

    if durable == false,
      do: base ++ [{Sampler, [history: __MODULE__.History] ++ Keyword.take(opts, [:interval_ms])}],
      else: base
  end

  defp inspection_children(false, false), do: []

  defp inspection_children(history, durable_query) do
    sources =
      if(history == false, do: [], else: [history: __MODULE__.History]) ++
        if durable_query == false, do: [], else: [durable: durable_query]

    [{Inspection, sources}]
  end

  defp durable_children(false, _history), do: []

  defp durable_children(opts, history) do
    history = if history == false, do: nil, else: __MODULE__.History
    [{Wotex.Lab.Metrics.GreptimeBridge, Durable.child_options(opts, history)}]
  end
end
