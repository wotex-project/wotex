defmodule Wotex.Runtime.Selection do
  @moduledoc "Immutable result of deterministic Interaction Affordance Form selection."

  alias Wotex.Form
  alias Wotex.Runtime.BindingProfile

  @opaque t :: %__MODULE__{
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
