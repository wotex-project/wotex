defmodule Wotex.OPCUA.Browse.Page do
  @moduledoc """
  Holds one typed native Browse page in server order.

  A continuation identifies the next page on the original persistent Session.
  Releasing that handle or closing the Session bounds remote cursor state.
  """

  @enforce_keys [:references, :status, :continuation]
  defstruct [:references, :status, :continuation]

  @type t :: %__MODULE__{
          references: [Wotex.OPCUA.Binary.Reference.t()],
          status: 0..4_294_967_295,
          continuation: nil | Wotex.OPCUA.Browse.Continuation.t()
        }
end
