defmodule Wotex.Thread.Session do
  @moduledoc """
  Carries the client handle and timeout for one Thread management connection.

  `Wotex.Thread.connect/1` creates a `t:t/0` after the selected
  `Wotex.Thread.Client` accepts its configuration. The `client` field identifies
  the implementation, `handle` contains its opaque connection state, and
  `timeout` bounds each call made through `Wotex.Thread.send/2`.

  The struct is an explicit caller-held capability. It is not registered
  globally and does not itself own an OpenThread daemon, radio, interface, or
  network credentials. Its inspection representation omits the opaque handle
  so socket state and possible sensitive transport details are not printed.
  The consumer releases resources with `Wotex.Thread.disconnect/1` or uses
  `Wotex.Thread.with_connection/2` for deterministic cleanup.
  """

  @derive {Inspect, only: [:client, :timeout]}
  @enforce_keys [:client, :handle, :timeout]
  defstruct [:client, :handle, :timeout]

  @type t :: %__MODULE__{client: module(), handle: term(), timeout: pos_integer()}

  @doc "Validates the exact Session shape without consulting or starting its client."
  @spec validate(term()) :: :ok | {:error, Wotex.Thread.Error.t()}
  def validate(%__MODULE__{client: client, timeout: timeout} = session)
      when map_size(session) == 4 and is_atom(client) and client not in [nil, true, false] and
             is_integer(timeout) and timeout in 1..60_000,
      do: :ok

  def validate(_), do: {:error, Wotex.Thread.Error.new(:invalid_session)}
end
