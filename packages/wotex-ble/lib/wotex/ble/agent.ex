defmodule Wotex.BLE.Agent do
  @moduledoc """
  Defines the explicit consumer decision boundary for one BlueZ pairing challenge.

  Implement `decide/2` in a consumer module and supply `{module, config}` to the
  pairing request. There is no default acceptance policy. Pairing implementations must invoke
  the callback in a monitored worker bounded by the pairing deadline; a crash,
  rejection, incompatible reply or timeout rejects the challenge.

  The challenge contains the exact selected peer and its typed prompt. Only a
  request for a PIN or passkey admits the corresponding value reply. Display and
  confirmation prompts require an explicit `:accept` or `:reject`; acknowledging
  a display makes no claim of user confirmation or authentication strength.
  """

  alias Wotex.BLE.Challenge

  @type decision :: :accept | :reject | {:passkey, 0..999_999} | {:pin, binary()}

  @doc "Decides one typed challenge using consumer-owned policy and configuration."
  @callback decide(Challenge.t(), term()) :: decision()
end
