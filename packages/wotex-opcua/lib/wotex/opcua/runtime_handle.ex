defmodule Wotex.OPCUA.RuntimeHandle do
  @moduledoc """
  Opaque Runtime observation handle for one `Wotex.OPCUA.RuntimeRelay`.

  The handle names the relay process and the generation reference created when
  it was started. It carries no Session, subscription, credential or native SDK
  value, and `inspect/1` shows none of its fields.
  """

  @derive {Inspect, only: []}
  @enforce_keys [:pid, :generation]
  defstruct [:pid, :generation]

  @type t :: %__MODULE__{pid: pid(), generation: reference()}
end
