defmodule Wotex.Directory.Expiry do
  @moduledoc """
  Result of one caller-invoked bounded expiry operation.

  A `t:t/0` records the selected `:purge` or `:retain` strategy, the
  cutoff returned by the configured `Wotex.Directory.Clock`, and the bounded
  list of `Wotex.Directory.Entry` values selected by the operation. The value
  is transport-neutral and preserves the evidence needed by a consumer to
  report or audit the decision.

  Expiry is evaluated only when the consumer calls `Wotex.Directory.expire/3`. Constructing or loading the library does
  not start a scheduler. A `:purge` result records entries removed through the
  repository port; a `:retain` result records entries marked `:expired`,
  with their version advanced on the first transition. The result does not assert that external caches or replicas have
  applied the same decision.
  """

  alias Wotex.Directory.Entry

  @enforce_keys [:strategy, :cutoff, :entries]
  defstruct [:strategy, :cutoff, :entries]

  @type t :: %__MODULE__{
          strategy: :purge | :retain,
          cutoff: DateTime.t(),
          entries: [Entry.t()]
        }
end
