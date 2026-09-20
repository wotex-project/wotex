defmodule Wotex.Thread.OpenThread do
  @moduledoc """
  Owns an explicitly configured Linux OpenThread host process.

  Build the packaged native host with `mix wotex.thread.native.build --workspace ABS`
  (the package alias is `mix wotex.native.build`) in an explicit Linux workspace.
  Supply its absolute executable path, radio URL, interface, storage path/mode
  and owner to `connect/1`. A successful connection has acquired its SDK
  resources and supports non-secret inspection. Closing it releases its
  owned SDK, radio descendants and interface while preserving durable settings.

  `start_link/1` supports caller supervision. `session/1` waits for successful
  SDK acquisition. Loading the library starts nothing. Explicit APIs support
  Dataset validation/export, enablement, network formation, management updates,
  commissioner admissions and Joiner attempts, while native State subscriptions
  deliver bounded, non-secret snapshots. Joiner success is reported only by the
  final SDK callback and does not promise subsequent Thread attachment.
  """

  @behaviour Wotex.Thread.Client
  alias Wotex.Thread.{Error, Session}
  alias Wotex.Thread.OpenThread.Connection

  @opaque handle :: %Connection{pid: pid(), reference: reference(), generation: 1}

  @doc "Acquires the explicitly configured native SDK and returns its opaque handle."
  @impl Wotex.Thread.Client
  @spec connect(term()) :: {:ok, handle()} | {:error, Error.t()}
  def connect(options) do
    with {:ok, pid} <- Connection.start(options, :unlinked),
         {:ok, session} <- Connection.session(pid),
         do: {:ok, session.handle}
  end

  @doc "Starts a linked session owner; call session/1 to await SDK acquisition."
  @spec start_link(term()) :: {:ok, pid()} | {:error, Error.t()}
  def start_link(options), do: Connection.start(options, :link)

  @doc "Returns a temporary worker specification; failed generations never restart automatically."
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(options),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      type: :worker,
      shutdown: 1000
    }

  @doc "Returns the acquired Session from its explicitly supervised owner process."
  @spec session(term()) :: {:ok, Session.t()} | {:error, Error.t()}
  defdelegate session(pid), to: Connection

  @doc "Executes one validated native request under a single finite deadline."
  @impl Wotex.Thread.Client
  @spec request(term(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  defdelegate request(handle, message, timeout), to: Connection

  @doc "Registers a native State subscription for `receiver` with a bounded delivery queue."
  @spec subscribe(term(), pid(), 1..10_000, 1..60_000) ::
          {:ok, Wotex.Thread.Subscription.t()} | {:error, Error.t()}
  defdelegate subscribe(handle, receiver, queue_limit, timeout), to: Connection

  @doc "Cancels a native State subscription and waits for its retirement barrier."
  @spec unsubscribe(term(), term(), 1..60_000) :: :ok | {:error, Error.t()}
  defdelegate unsubscribe(handle, subscription, timeout), to: Connection

  @doc "Closes an owned generation and waits for bounded native resource cleanup."
  @impl Wotex.Thread.Client
  @spec disconnect(term()) :: :ok | {:error, Error.t()}
  defdelegate disconnect(handle), to: Connection
end
