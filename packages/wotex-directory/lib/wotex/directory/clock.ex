defmodule Wotex.Directory.Clock do
  @moduledoc """
  Consumer time port used for every registration and expiry decision.

  `c:now/1` receives consumer-supplied state and returns `{:ok, datetime}`
  or an error; it does not return updated state. `Wotex.Directory` calls the port when
  it needs an instant for registration metadata, expiry evaluation, or a
  bounded purge. Passing time through this behavior keeps those decisions
  explicit and independently testable.

  A clock implementation owns access to its time source and error
  normalization. It must not hide a fallback to the system clock or return an
  ambiguous local time. The directory does not cache the result as global
  state. Tests can supply a fixed implementation; production consumers may use
  `Wotex.Directory.Clock.System` when direct UTC wall-clock observation matches
  their policy.
  """

  @doc "Returns the consumer-owned current instant used by directory decisions."
  @callback now(state :: term()) :: {:ok, DateTime.t()} | {:error, term()}
end
