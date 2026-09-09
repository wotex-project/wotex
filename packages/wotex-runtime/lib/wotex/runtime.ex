defmodule Wotex.Runtime do
  @moduledoc """
  Binding-neutral W3C Web of Things interaction mechanics.

  The runtime composes validated Thing Descriptions with explicit binding
  profiles, credential providers, and transports. It deterministically selects
  a compatible Interaction Affordance or top-level Thing Form, creates a
  credential-free request, resolves credentials for that request, and invokes a
  consumer port.

  It does not own persistence, authorization, credential custody, protocol
  implementations, retry scheduling, or canonical Thing state. Synchronous
  interactions run in the caller. Long-lived observations and Event
  subscriptions exist only when a consumer starts a returned child
  specification under its own supervisor.

  Operation atoms follow the TD 1.1 vocabulary and are listed by
  `operations/0`. Transport completion is protocol evidence only; it is not
  proof of a physical Action effect or accepted Property truth.
  """

  @affordance_operations ~w(readproperty writeproperty observeproperty unobserveproperty invokeaction queryaction cancelaction subscribeevent unsubscribeevent)a
  @thing_operations ~w(readallproperties writeallproperties readmultipleproperties writemultipleproperties observeallproperties unobserveallproperties queryallactions subscribeallevents unsubscribeallevents)a
  @operations @affordance_operations ++ @thing_operations

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
          | :readallproperties
          | :writeallproperties
          | :readmultipleproperties
          | :writemultipleproperties
          | :observeallproperties
          | :unobserveallproperties
          | :queryallactions
          | :subscribeallevents
          | :unsubscribeallevents

  @type thing_operation ::
          :readallproperties
          | :writeallproperties
          | :readmultipleproperties
          | :writemultipleproperties
          | :observeallproperties
          | :unobserveallproperties
          | :queryallactions
          | :subscribeallevents
          | :unsubscribeallevents

  @type interaction_type :: :thing | :property | :action | :event

  @doc """
  Returns the complete supported TD 1.1 operation vocabulary as atoms.

  The order is stable and groups Property operations before Action, Event, and
  Thing-level operations. A binding profile declares the subset it implements.
  """
  @spec operations() :: [operation(), ...]
  def operations, do: @operations

  @doc "Returns the exact TD 1.1 Thing-level meta-interaction operations."
  @spec thing_operations() :: [thing_operation(), ...]
  def thing_operations, do: @thing_operations

  @doc "Returns the TD interaction context for an operation, or `nil` when unsupported."
  @spec interaction_type(atom()) :: interaction_type() | nil
  def interaction_type(operation)
      when operation in ~w(readproperty writeproperty observeproperty unobserveproperty)a,
      do: :property

  def interaction_type(operation)
      when operation in ~w(invokeaction queryaction cancelaction)a,
      do: :action

  def interaction_type(operation)
      when operation in ~w(subscribeevent unsubscribeevent)a,
      do: :event

  def interaction_type(operation) when operation in @thing_operations, do: :thing
  def interaction_type(_), do: nil
end
