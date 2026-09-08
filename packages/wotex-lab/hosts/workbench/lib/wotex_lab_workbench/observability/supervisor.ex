defmodule WotexLabWorkbench.Observability.Supervisor do
  @moduledoc """
  Explicit host-owned PromEx activation. No public listener, database, polling
  of application internals or model service starts here. The normalized relay
  follows the collector in a one-for-all lifecycle; neither can outlive its host.
  Optional local history shares that lifecycle: a restart discards the whole
  volatile cohort, not just its sampler. Browser sessions cannot activate it.
  `:scrape` separately admits an authenticated loopback-only operator listener.
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

  alias WotexLabWorkbench.Observability.{Inspection, PromEx, Relay, Sampler, Scrape}

  @doc "Starts capture/relay; explicit options add bounded history, scrape and BeamLens surfaces."
  @spec start_link(keyword()) :: Supervisor.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- Options.validate(opts, [:history, :scrape, :beamlens]),
         :ok <- history_options(Keyword.get(opts, :history, false)),
         :ok <- scrape_options(Keyword.get(opts, :scrape, false)),
         :ok <- beamlens_options(Keyword.get(opts, :beamlens, false)),
         :ok <-
           dependencies(Keyword.get(opts, :history, false), Keyword.get(opts, :beamlens, false)),
         do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    children =
      [PromEx, {Relay, []}] ++
        history_children(Keyword.get(opts, :history, false)) ++
        scrape_children(Keyword.get(opts, :scrape, false)) ++
        beamlens_children(Keyword.get(opts, :beamlens, false))

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp history_options(false), do: :ok

  defp history_options(opts),
    do: Options.validate(opts, [:interval_ms, :max_snapshots, :max_bytes, :max_queries])

  defp scrape_options(false), do: :ok
  defp scrape_options(opts), do: Scrape.validate(opts)

  defp beamlens_options(false), do: :ok

  defp beamlens_options(%{primary: primary, clients: clients})
       when is_binary(primary) and is_list(clients) and clients != [],
       do: :ok

  defp beamlens_options(_opts),
    do: {:error, Error.new(:invalid_beamlens, :construction, "BeamLens options are invalid")}

  defp dependencies(false, beamlens) when beamlens != false,
    do:
      {:error, Error.new(:beamlens_requires_history, :construction, "BeamLens needs local history")}

  defp dependencies(_history, _beamlens), do: :ok

  defp scrape_children(false), do: []
  defp scrape_children(opts), do: [{Scrape, opts}]

  defp beamlens_children(false), do: []

  defp beamlens_children(registry) do
    [
      Status,
      ContextStore,
      {BeamlensSupervisor, client_registry: registry},
      Broker
    ]
  end

  defp history_children(false), do: []

  defp history_children(opts) do
    history =
      Keyword.take(opts, [:max_snapshots, :max_bytes, :max_queries]) ++
        [id: :operator, name: __MODULE__.History, instance: "workbench", instance_slot: 0]

    [
      {History, history},
      {Inspection, history: __MODULE__.History},
      {Sampler, [history: __MODULE__.History] ++ Keyword.take(opts, [:interval_ms])}
    ]
  end
end
