defmodule Wotex.Runtime.Request do
  @moduledoc """
  The immutable, credential-free request passed to a transport port.

  A request records the selected W3C WoT operation, Interaction Affordance,
  Form, resolved href, binding profile, caller identity, deadline, and input.
  Credential material is deliberately absent; `Wotex.Runtime.ExecutionContext`
  carries it only during the immediate port call.

  Consumers normally receive this value in a `Wotex.Runtime.Transport`
  callback rather than constructing it directly. Treat its fields as
  read-only operation inputs.
  """

  alias Wotex.Form
  alias Wotex.Runtime.{BindingProfile, Context, Selection}

  @type t :: %__MODULE__{
          operation: atom(),
          affordance_type: :property | :action | :event,
          affordance_name: String.t(),
          form: Form.t(),
          resolved_href: String.t(),
          profile: BindingProfile.t(),
          request_id: String.t(),
          deadline: Context.deadline(),
          input: term()
        }

  @enforce_keys [
    :operation,
    :affordance_type,
    :affordance_name,
    :form,
    :resolved_href,
    :profile,
    :request_id,
    :deadline,
    :input
  ]
  defstruct @enforce_keys

  @doc false
  @spec from_selection(Selection.t(), Context.t(), term()) :: t()
  def from_selection(%Selection{} = selection, %Context{} = context, input) do
    %__MODULE__{
      operation: selection.operation,
      affordance_type: selection.affordance_type,
      affordance_name: selection.affordance_name,
      form: selection.form,
      resolved_href: selection.resolved_href,
      profile: selection.profile,
      request_id: Context.request_id(context),
      deadline: Context.deadline(context),
      input: input
    }
  end
end
