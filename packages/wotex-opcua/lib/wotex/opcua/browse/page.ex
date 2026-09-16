defmodule Wotex.OPCUA.Browse.Page do
  @moduledoc """
  Holds one complete typed native Browse page in server order.

  The current native client returns this value only when the server supplies no
  continuation. A future owner-bound continuation handle will occupy the
  `continuation` field; callers must not infer multi-page support from its
  presence in this structure.
  """

  @enforce_keys [:references, :status, :continuation]
  defstruct [:references, :status, :continuation]

  @type t :: %__MODULE__{
          references: [Wotex.OPCUA.Binary.Reference.t()],
          status: 0..4_294_967_295,
          continuation: nil
        }
end
