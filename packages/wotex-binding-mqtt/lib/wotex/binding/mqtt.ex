defmodule Wotex.Binding.MQTT do
  @moduledoc """
  Caller-owned MQTT protocol binding for W3C Web of Things.

  The package maps MQTT Forms to immutable commands and implements the
  `Wotex.Runtime.Transport` callbacks through a consumer-supplied client port.
  Loading this module starts no process and opens no connection.
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
