defmodule Wotex.Matter.Native.Handle do
  @moduledoc """
  Opaque capability for one explicitly started first-party Matter controller.

  The inspection representation excludes its process identity and generation
  token. Consumers should retain the handle only for the lifetime of the
  `Wotex.Matter.Session` that contains it.
  """

  @derive {Inspect, only: [:fabric_id]}
  @enforce_keys [:pid, :generation, :fabric_id]
  defstruct [:pid, :generation, :fabric_id]

  @type t :: %__MODULE__{
          pid: pid(),
          generation: String.t(),
          fabric_id: pos_integer()
        }
end
