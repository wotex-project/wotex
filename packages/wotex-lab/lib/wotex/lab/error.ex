defmodule Wotex.Lab.Error do
  @moduledoc "Structured errors at Lab construction and composition boundaries."

  @typedoc "Stable code and phase; the explanatory message contains no supplied payload."
  @type t :: %__MODULE__{code: atom(), phase: atom(), message: String.t()}
  @enforce_keys [:code, :phase, :message]
  defstruct @enforce_keys

  @doc "Builds an error without embedding caller configuration or secrets."
  @spec new(atom(), atom(), String.t()) :: t()
  def new(code, phase, message), do: %__MODULE__{code: code, phase: phase, message: message}
end
