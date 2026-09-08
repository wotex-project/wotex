defmodule Wotex.Modbus.Session do
  @moduledoc "Consumer-held reference to an explicitly owned Modbus TCP connection."

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
