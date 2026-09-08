defmodule WotexLabWorkbench.Observability.Supervisor do
  @moduledoc """
  Explicit host-owned PromEx activation. No public listener, database, polling
  of application internals or model service starts here. The normalized relay
  follows the collector in a one-for-all lifecycle; neither can outlive its host.
  Optional local history shares that lifecycle: a restart discards the whole
  volatile cohort, not just its sampler. Browser sessions cannot activate it.
  """

  use Supervisor

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.History
  alias WotexLabWorkbench.Observability.{PromEx, Relay, Sampler}

  @doc "Starts capture/relay; `history: []` explicitly adds bounded operator-only history."
  @spec start_link(keyword()) :: Supervisor.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- Options.validate(opts, [:history]),
         :ok <- history_options(Keyword.get(opts, :history, false)),
         do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    children = [PromEx, {Relay, []}] ++ history_children(Keyword.get(opts, :history, false))
    Supervisor.init(children, strategy: :one_for_all)
  end

  defp history_options(false), do: :ok

  defp history_options(opts),
    do: Options.validate(opts, [:interval_ms, :max_snapshots, :max_bytes, :max_queries])

  defp history_children(false), do: []

  defp history_children(opts) do
    history =
      Keyword.take(opts, [:max_snapshots, :max_bytes, :max_queries]) ++
        [id: :operator, name: __MODULE__.History, instance: "workbench", instance_slot: 0]

    [
      {History, history},
      {Sampler, [history: __MODULE__.History] ++ Keyword.take(opts, [:interval_ms])}
    ]
  end
end
