defmodule Wotex.Matter.Native.OneshotHandle do
  @moduledoc """
  Opaque configuration for per-operation native Matter controller ownership.

  No process or storage lock belongs to this handle. Each admitted concrete
  read, write or invoke opens its existing store and closes that controller
  before returning. The inspection representation excludes executable, storage
  and trust paths. Consumers obtain this value through `Wotex.Matter.Native`.
  """

  @derive {Inspect, only: [:fabric_id]}
  @enforce_keys [:options, :fabric_id]
  defstruct [:options, :fabric_id]

  @type t :: %__MODULE__{options: keyword(), fabric_id: pos_integer()}
end
