defmodule Wotex.Directory.Expiry do
  @moduledoc """
  Result of one caller-invoked bounded expiry operation.
  """

  alias Wotex.Directory.Entry

  @enforce_keys [:strategy, :cutoff, :entries]
  defstruct [:strategy, :cutoff, :entries]

  @type t :: %__MODULE__{
          strategy: :purge | :retain,
          cutoff: DateTime.t(),
          entries: [Entry.t()]
        }
end
