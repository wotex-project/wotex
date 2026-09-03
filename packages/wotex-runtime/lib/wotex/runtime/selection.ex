defmodule Wotex.Runtime.Selection do
  @moduledoc """
  The immutable result of deterministic Interaction Affordance Form selection.

  A selection binds one declared W3C WoT operation to the first compatible Form
  in Thing Description order and the first compatible binding profile in
  consumer order. It includes the inherited security declaration needed by a
  credential port.

  Compatibility is descriptive: this value does not authorize execution,
  resolve credentials, open a transport, or establish canonical Thing state.
  """

  alias Wotex.Form
  alias Wotex.Runtime.BindingProfile

  @type t :: %__MODULE__{
          affordance_type: :property | :action | :event,
          affordance_name: String.t(),
          affordance: map(),
          operation: atom(),
          form: Form.t(),
          resolved_href: String.t(),
          profile: BindingProfile.t(),
          security: map()
        }

  @enforce_keys [
    :affordance_type,
    :affordance_name,
    :affordance,
    :operation,
    :form,
    :resolved_href,
    :profile,
    :security
  ]
  defstruct @enforce_keys
end
