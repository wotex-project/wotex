defmodule Wotex.Modbus.Session do
  @moduledoc """
  Carries the process, Unit Identifier, and timeout for one Modbus TCP session.

  `Wotex.Modbus.connect/1` returns a `t:t/0` after starting a scoped
  `Wotex.Modbus.Connection`. The `pid` identifies that socket owner, `unit_id`
  selects the destination unit for commands, and `timeout` bounds each request
  including time spent waiting behind another serialized exchange.

  `validate/1` checks field types and ranges at the public boundary. The
  connection separately verifies local process ownership before dispatch or
  cleanup. Invalid fields or foreign live processes return
  `Wotex.Modbus.Error`. A session is an
  explicit caller-held capability, not a globally registered client. The
  consumer owns its larger supervision and authorization context and must call
  `Wotex.Modbus.disconnect/1` to release the socket. Possessing a session does
  not establish permission to read or write any address.
  """

  @enforce_keys [:pid, :unit_id, :timeout]
  defstruct [:pid, :unit_id, :timeout]

  @type t :: %__MODULE__{pid: pid(), unit_id: 1..247 | 255, timeout: pos_integer()}

  @doc "Validates the public session fields before dispatching an operation."
  @spec validate(term()) :: :ok | {:error, Wotex.Modbus.Error.t()}
  def validate(%__MODULE__{pid: pid, unit_id: unit, timeout: timeout})
      when is_pid(pid) and is_integer(unit) and (unit in 1..247 or unit == 255) and
             is_integer(timeout) and timeout in 1..60_000,
      do: :ok

  def validate(_), do: {:error, Wotex.Modbus.Error.new(:invalid_session)}
end
