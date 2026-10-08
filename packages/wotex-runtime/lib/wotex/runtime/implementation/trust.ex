defmodule Wotex.Runtime.Implementation.Trust do
  @moduledoc """
  Consumer pin or completed update-verifier decision.

  The receipt reports consumer authority. It cannot be manufactured from publisher metadata to establish trust.
  """
  alias Wotex.Runtime.Implementation.{Error, Record}
  @type t :: %__MODULE__{value: map(), sha256: String.t()}
  defstruct [:value, :sha256]

  @doc "Validates the closed receipt map and computes its complete JCS identity."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(value), do: Record.new(__MODULE__, value)
end
