defmodule Wotex.Matter.Session do
  @moduledoc """
  Carries the client handle and timeout for one Matter connection.

  `Wotex.Matter.connect/1` creates a `t:t/0` after the selected
  `Wotex.Matter.Client` accepts its configuration. The `client` field identifies
  the implementation, `handle` contains its opaque controller state, and
  `timeout` is supplied to the client for each call through
  `Wotex.Matter.send/2`. The client must enforce that deadline.

  The struct is an explicit caller-held capability. It is not registered
  globally and does not itself own a fabric, credential, or secure session. Its
  inspection representation omits the opaque handle so controller state and
  possible credential-bearing details are not printed. The consumer releases
  owned resources with `Wotex.Matter.disconnect/1` or uses
  `Wotex.Matter.with_connection/2` for deterministic cleanup.
  """

  @derive {Inspect, only: [:client, :timeout]}
  @enforce_keys [:client, :handle, :timeout]
  defstruct [:client, :handle, :timeout]

  @type t :: %__MODULE__{client: module(), handle: term(), timeout: pos_integer()}
end
