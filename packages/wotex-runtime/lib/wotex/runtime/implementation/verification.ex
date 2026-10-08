defmodule Wotex.Runtime.Implementation.Verification do
  @moduledoc """
  Bounded receipt from an explicit native deployment verifier.

  Construction validates receipt syntax; it does not verify an artifact, signature or operating-system guarantee.
  """
  alias Wotex.Runtime.Implementation.{Error, Record}
  @type t :: %__MODULE__{value: map(), sha256: String.t()}
  defstruct [:value, :sha256]

  @doc "Validates the closed receipt map and computes its complete JCS identity."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(value), do: Record.new(__MODULE__, value)
end
