defmodule Wotex.Nx.ActionProposal do
  @moduledoc "Inert proposal for a consumer to evaluate before invoking a Thing Action."

  @opaque t :: %__MODULE__{
            id: String.t(),
            thing_id: String.t(),
            action_name: String.t(),
            input: term(),
            proposed_at: integer(),
            metadata: map()
          }

  @enforce_keys [:id, :thing_id, :action_name, :input, :proposed_at, :metadata]
  defstruct @enforce_keys
end
