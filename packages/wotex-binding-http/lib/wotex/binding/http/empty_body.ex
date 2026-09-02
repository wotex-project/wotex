defmodule Wotex.Binding.HTTP.EmptyBody do
  @moduledoc "Explicit marker for an interaction with no HTTP message body."

  @opaque t :: %__MODULE__{}
  defstruct []

  @doc "Returns the immutable empty-body marker."
  @spec new() :: t()
  def new, do: %__MODULE__{}
end
