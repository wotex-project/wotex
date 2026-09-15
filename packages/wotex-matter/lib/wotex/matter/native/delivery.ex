defmodule Wotex.Matter.Native.Delivery do
  @moduledoc """
  Carries one unacknowledged native report to its internal stream owner.

  The connection binds this opaque value to its session generation, subscription
  reference, report sequence and a unique acknowledgement token. An ordinary
  stream owner validates admission before returning the token to the connection,
  which alone forwards the public tuple. The Runtime relay returns its token
  after the Runtime owner validates and consumes its projected frame. Sending
  a report to a suspended owner does not release native credit.
  This internal value starts no process and contains no native pointer.
  """

  @derive {Inspect, only: [:sequence]}
  @enforce_keys [:connection, :generation, :reference, :sequence, :token, :value]
  defstruct [:connection, :generation, :reference, :sequence, :token, :value]

  @opaque t :: %__MODULE__{
            connection: pid(),
            generation: binary(),
            reference: reference(),
            sequence: pos_integer(),
            token: reference(),
            value: term()
          }
end
