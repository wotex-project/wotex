defmodule Wotex.Runtime.Implementation.Registration do
  @moduledoc """
  Explicit installed implementation, qualified cells and deployment ceilings.

  Registration is supplied by the consumer. Descriptor bytes never create it.
  """
  alias Wotex.Runtime.Implementation.{Error, Record}
  @type t :: %__MODULE__{value: map(), sha256: String.t()}
  defstruct [:value, :sha256]

  @doc "Validates the closed receipt map and computes its complete JCS identity."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(value), do: Record.new(__MODULE__, value)
end
