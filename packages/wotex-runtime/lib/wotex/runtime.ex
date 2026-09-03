defmodule Wotex.Runtime do
  @moduledoc """
  Binding-neutral W3C Web of Things interaction mechanics.

  The runtime composes validated Thing Descriptions with explicit binding
  profiles, credential providers, and transports. It deterministically selects
  a compatible Form, creates a credential-free request, resolves credentials
  just in time, and invokes a consumer port.

  It does not own persistence, authorization, credential custody, protocol
  implementations, retry scheduling, or canonical Thing state. Synchronous
  interactions run in the caller. Long-lived observations and Event
  subscriptions exist only when a consumer starts a returned child
  specification under its own supervisor.

  Operation atoms follow the TD 1.1 vocabulary and are listed by
  `operations/0`. Transport completion is protocol evidence only; it is not
  proof of a physical Action effect or accepted Property truth.
  """

  @operations ~w(readproperty writeproperty observeproperty unobserveproperty invokeaction queryaction cancelaction subscribeevent unsubscribeevent)a

  @type operation ::
          :readproperty
          | :writeproperty
          | :observeproperty
          | :unobserveproperty
          | :invokeaction
          | :queryaction
          | :cancelaction
          | :subscribeevent
          | :unsubscribeevent

  @doc """
  Returns the complete supported TD 1.1 operation vocabulary as atoms.

  The order is stable and groups Property operations before Action and Event
  operations. A binding profile declares the subset it implements.
  """
  @spec operations() :: [operation(), ...]
  def operations, do: @operations
end
