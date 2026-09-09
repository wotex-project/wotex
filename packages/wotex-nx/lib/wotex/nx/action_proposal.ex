defmodule Wotex.Nx.ActionProposal do
  @moduledoc """
  An inert proposal derived from numerical output for a Thing Action.

  A proposal deliberately carries no callback, authorization decision, or
  execution state. The consumer validates it against current Thing state and
  policy before choosing whether to invoke the named Action.

  `Wotex.Nx.Decoder` produces the value only after a tensor satisfies an
  action-proposal `Wotex.Nx.OutputSchema`. The proposal preserves a
  caller-supplied ID, the exact Thing and Action names, the decoded input, the
  proposal time coordinate, and output metadata.

  The struct is evidence of a numerical recommendation, not permission or
  proof of an effect. An application should bind it to current observations,
  schema and model provenance, a policy decision, and an attempt identity
  before dispatch; rejection and observed effect remain separate records.
  """

  @typedoc "A caller-identified, timestamped Action proposal and its inert input value."
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

  @doc "Returns the action proposal fields as a plain map; a read-only view, not an admission boundary."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value), do: Map.from_struct(value)
end
