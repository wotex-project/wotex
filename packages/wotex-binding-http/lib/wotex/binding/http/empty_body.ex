defmodule Wotex.Binding.HTTP.EmptyBody do
  @moduledoc """
  Marks an interaction that deliberately has no HTTP message body.

  The marker keeps absence distinct from Elixir `nil`, which is the valid JSON
  value `null` when used as an Action input.
  """

  @type t :: %__MODULE__{}
  defstruct []

  @doc "Returns the immutable empty-body marker."
  @spec new() :: t()
  def new, do: %__MODULE__{}
end
