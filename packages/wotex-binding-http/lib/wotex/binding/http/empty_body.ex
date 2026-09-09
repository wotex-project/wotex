defmodule Wotex.Binding.HTTP.EmptyBody do
  @moduledoc """
  Marks an interaction that deliberately has no HTTP message body.

  The marker keeps absence distinct from Elixir `nil`, which is the valid JSON
  value `null` when used as an Action input.

  `new/0` returns the sole stateless `t:t/0` representation. Request mapping
  uses the marker when the selected operation carries no representation, while
  an explicit `nil` input is encoded as JSON `null`. This distinction prevents
  a transport adapter from discarding a meaningful Action argument or adding a
  body where the Form and operation define none.

  The marker is a protocol value shared across the public request
  boundary. It does not select a Content-Type, set Content-Length, or control
  transfer framing. Those HTTP details remain with
  `Wotex.Binding.HTTP.Request`, the mapping layer, and the consumer-supplied
  client.
  """

  @type t :: %__MODULE__{}
  defstruct []

  @doc "Returns the immutable empty-body marker."
  @spec new() :: t()
  def new, do: %__MODULE__{}
end
