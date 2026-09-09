defmodule Wotex.Binding.MQTT do
  @moduledoc """
  Caller-owned MQTT protocol binding for W3C Web of Things.

  The package maps MQTT Forms to immutable commands and implements the
  `Wotex.Runtime.Transport` callbacks through a consumer-supplied client port.
  Loading this module starts no process and opens no connection.

  `profile/0` returns the binding profile used by Runtime Form selection. It
  admits `mqtt` and `mqtts` schemes, JSON representations, and the Property,
  Action, and Event operations implemented by the package. The profile records
  mapping capability; it does not choose a broker connection, authenticate a
  session, authorize an operation, or establish that a retained value is
  current.

  The consumer configures `Wotex.Binding.MQTT.Transport` with a
  `Wotex.Binding.MQTT.TransportConfig` and owns the client session, supervision,
  credentials, reconnect policy, and broker trust. The mapping vocabulary is a
  dated editor's draft, so this package makes no W3C binding-registry or Profile
  conformance claim.
  """

  alias Wotex.Runtime.BindingProfile

  @operations [
    :readproperty,
    :writeproperty,
    :observeproperty,
    :unobserveproperty,
    :invokeaction,
    :subscribeevent,
    :unsubscribeevent
  ]

  @doc "Returns the Runtime binding profile for JSON over MQTT."
  @spec profile() :: BindingProfile.t()
  def profile do
    {:ok, profile} =
      BindingProfile.new(
        id: :mqtt,
        schemes: ["mqtt", "mqtts"],
        operations: @operations,
        media_types: ["application/json"]
      )

    profile
  end
end
