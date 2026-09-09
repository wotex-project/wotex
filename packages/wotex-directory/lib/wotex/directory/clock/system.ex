defmodule Wotex.Directory.Clock.System do
  @moduledoc """
  Stateless UTC system-clock implementation.

  `Wotex.Directory.Clock.System` implements `Wotex.Directory.Clock` with
  `DateTime.utc_now/0`. `c:Wotex.Directory.Clock.now/1` ignores the supplied
  state and returns the observed UTC instant as a tagged success value. It is
  suitable when a consumer explicitly chooses the host system clock for
  registration and expiry decisions.

  The module reads time only when `now/1` is called. Loading the package starts
  no process and schedules no expiry work. The returned instant is an
  observation, not a monotonic deadline or proof that the host clock is
  synchronized. Consumers that require deterministic tests, an authoritative
  time service, or error-producing clock behavior should provide a different
  implementation of `Wotex.Directory.Clock`.
  """

  @behaviour Wotex.Directory.Clock

  @impl true
  def now(_state), do: {:ok, DateTime.utc_now()}
end
