defmodule Wotex.Thread.Session do
  @moduledoc "Explicit client handle. Inspect omits transport state and credentials."

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
