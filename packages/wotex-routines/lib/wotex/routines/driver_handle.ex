defmodule Wotex.Routines.DriverHandle do
  @moduledoc "Opaque local admission handle for one explicitly started driver. It is neither a grant nor portable state."

  @enforce_keys [:pid, :token, :counter, :capacity]
  defstruct [:pid, :token, :counter, :capacity]

  @type t :: %__MODULE__{
          pid: pid(),
          token: reference(),
          counter: reference(),
          capacity: pos_integer()
        }
end
