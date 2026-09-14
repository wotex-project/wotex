defmodule Wotex.Matter.OnboardingMaterial do
  @moduledoc """
  Secret onboarding material returned after an enhanced commissioning window opens.

  The values are intentionally redacted from `Inspect`. Applications must treat
  the complete struct as a secret and disclose it only to the intended
  commissioner.
  """

  @enforce_keys [:node_id, :setup_pin, :discriminator, :manual_code, :qr_code, :expires_in_s]
  defstruct [:node_id, :setup_pin, :discriminator, :manual_code, :qr_code, :expires_in_s]

  @type t :: %__MODULE__{
          node_id: pos_integer(),
          setup_pin: pos_integer(),
          discriminator: non_neg_integer(),
          manual_code: String.t(),
          qr_code: String.t(),
          expires_in_s: pos_integer()
        }

  defimpl Inspect do
    def inspect(_, _), do: "#Wotex.Matter.OnboardingMaterial<redacted>"
  end
end
