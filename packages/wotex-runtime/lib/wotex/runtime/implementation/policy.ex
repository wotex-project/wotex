defmodule Wotex.Runtime.Implementation.Policy do
  @moduledoc """
  Current consumer grants, security disposition and enforcement ceilings.

  Construction validates immutable decision data and does not grant access or inspect ambient policy.
  """
  alias Wotex.Runtime.Implementation.{Error, Record}
  @type t :: %__MODULE__{value: map(), sha256: String.t()}
  defstruct [:value, :sha256]

  @doc "Validates the closed receipt map and computes its complete JCS identity."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(value), do: Record.new(__MODULE__, value)
end
