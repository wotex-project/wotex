defmodule Wotex.Matter.Native.Delivery do
  @moduledoc """
  Carries one unacknowledged native report to the internal Runtime relay.

  The connection binds this opaque value to its session generation, subscription
  reference, report sequence and a unique acknowledgement token. The relay
  returns that token only after the Runtime owner validates and consumes its
  projected frame. Sending a report to a suspended relay does not release native
  credit. Ordinary named subscription deliveries retain their public tuple form.
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
