defmodule Wotex.BLE.CoreBluetooth do
  @moduledoc """
  Owns an explicitly selected CoreBluetooth native process and peripheral.

  Configuration requires a `Wotex.BLE.CoreBluetooth.Peer`, a fresh nonzero
  uint64 `generation`, `pairing: :system`, and absolute `executable`/`guardian`
  paths with their `executable_sha256`/`guardian_sha256` digests. Optional
  `permission` is `:require_authorized` (default) or `:request`; `timeout` is
  1..60,000 ms (default 5,000). The local `owner` defaults to the caller.

  Startup verifies both immutable artifacts and discovers bounded routes under
  one deadline. Loading starts nothing. The consumer provisions artifacts,
  chooses permission policy and supervises the connection. No scan, retry,
  automatic reconnect or manual pairing is implicit. Explicit subscriptions
  retain at most sixteen live streams and 64 shared report credits. Cancellation
  can retire the generation when a point operation occupies native control.
  Writes preserve the selected response mode; queue evidence proves no physical
  effect. Private peripheral identifiers and executable paths are not diagnostics.
  """
  @behaviour Wotex.BLE.Client
  alias Wotex.BLE.CoreBluetooth.Connection
  alias Wotex.BLE.Error

  @impl Wotex.BLE.Client
  defdelegate connect(options), to: Connection

  @impl Wotex.BLE.Client
  defdelegate request(handle, message, timeout), to: Connection

  @impl Wotex.BLE.Client
  defdelegate disconnect(handle), to: Connection

  @doc "Starts and links one explicitly owned connection after bounded startup."
  @spec start_link(term()) :: {:ok, pid()} | {:error, Error.t()}
  defdelegate start_link(options), to: Connection

  @doc "Returns the opaque handle of a live explicitly started connection."
  @spec session(term()) :: {:ok, Connection.t()} | {:error, Error.t()}
  defdelegate session(pid), to: Connection

  @doc "Returns the current complete generation-scoped discovery snapshot."
  @spec discover(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  defdelegate discover(handle, timeout), to: Connection

  @doc "Checks the live native owner without reconnecting."
  @spec health_check(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  defdelegate health_check(handle, timeout), to: Connection

  @doc "Starts an explicitly selected, bounded receiver-owned native stream."
  @spec subscribe(term(), term(), term()) :: {:ok, Wotex.BLE.Subscription.t()} | {:error, Error.t()}
  defdelegate subscribe(handle, request, timeout), to: Connection

  @doc "Fences delivery and joins native retirement for a same-session stream."
  @spec unsubscribe(term(), term()) :: :ok | {:error, Error.t()}
  defdelegate unsubscribe(handle, subscription), to: Connection
end
