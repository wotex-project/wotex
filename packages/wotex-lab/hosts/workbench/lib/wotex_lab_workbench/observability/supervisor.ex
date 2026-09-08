defmodule WotexLabWorkbench.Observability.Supervisor do
  @moduledoc """
  Explicit host-owned PromEx activation. No public listener, database, polling
  of application internals or model service starts here. The normalized relay
  follows the collector in a one-for-all lifecycle; neither can outlive its host.
  """

  use Supervisor

  alias Wotex.Lab.{Error, Options}
  alias WotexLabWorkbench.Observability.{PromEx, Relay}

  @doc "Starts the host's fixed custom-metric collector and relay."
  @spec start_link(keyword()) :: Supervisor.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- Options.validate(opts, []),
         do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl Supervisor
  def init([]), do: Supervisor.init([PromEx, {Relay, []}], strategy: :one_for_all)
end
