defmodule Wotex.OPCUA.Subscription do
  @moduledoc """
  Identifies one live monitored-item subscription on its native Session owner.

  A handle is returned only after the server accepted the subscription, its
  MonitoredItem and every revised parameter. It is bound to the owner process
  and its native generation; a handle from another owner or generation is
  rejected before protocol I/O. Deliveries to the receiver are
  `{:wotex_opcua, reference, {:ok, data_value, metadata}}` or one terminal
  `{:wotex_opcua, reference, {:error, error}}`. Inspection prints no field.
  """

  @derive {Inspect, only: []}
  @enforce_keys [:pid, :reference, :generation]
  defstruct [:pid, :reference, :generation]

  @type t :: %__MODULE__{pid: pid(), reference: reference(), generation: pos_integer()}
end
