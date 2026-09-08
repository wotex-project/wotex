defmodule Wotex.Modbus.Session do
  @moduledoc "Consumer-held reference to an explicitly owned Modbus TCP connection."

  @enforce_keys [:pid, :unit_id, :timeout]
  defstruct [:pid, :unit_id, :timeout]

  @type t :: %__MODULE__{pid: pid(), unit_id: 1..247 | 255, timeout: pos_integer()}
end
