defmodule Wotex.Directory.Mutation do
  @moduledoc """
  Transport-neutral result of a successful directory mutation.

  A `t:t/0` records the requested operation, its resulting status, and the
  affected `Wotex.Directory.Entry`. Register, replace, patch, and delete remain
  distinct operations, while the status reports whether the entry was created,
  replaced, patched, or deleted. The value contains directory semantics rather
  than an HTTP status or persistence return value.

  `Wotex.Directory` returns this struct only after authorization,
  optimistic-concurrency checks, Thing Description validation, and repository
  mutation have succeeded. The embedded entry preserves the accepted directory
  version and registration metadata. A mutation result does not imply that a
  transport response has been sent, that another replica has observed the
  change, or that the described Thing is reachable.
  """

  alias Wotex.Directory.Entry

  @enforce_keys [:operation, :status, :entry]
  defstruct [:operation, :status, :entry]

  @type operation :: :register | :replace | :patch | :delete
  @type status :: :created | :replaced | :patched | :deleted
  @type t :: %__MODULE__{operation: operation(), status: status(), entry: Entry.t()}
end
