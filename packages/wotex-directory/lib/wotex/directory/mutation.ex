defmodule Wotex.Directory.Mutation do
  @moduledoc """
  Transport-neutral result of a successful directory mutation.
  """

  alias Wotex.Directory.Entry

  @enforce_keys [:operation, :status, :entry]
  defstruct [:operation, :status, :entry]

  @type operation :: :register | :replace | :patch | :delete
  @type status :: :created | :replaced | :patched | :deleted
  @type t :: %__MODULE__{operation: operation(), status: status(), entry: Entry.t()}
end
