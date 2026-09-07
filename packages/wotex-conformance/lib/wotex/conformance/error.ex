defmodule Wotex.Conformance.Error do
  @moduledoc """
  Stable structured failure returned when a conformance contract cannot be
  constructed or an external target cannot be exercised safely.

  Match on `code`, `phase`, and `path`. `phase` names the contract stage that
  rejected the value and comes from `phases/0`. `path` is an RFC 6901 JSON
  Pointer string rooted at `/`, or `nil` when the failure does not address one
  member of a value.

  Messages are bounded static text and may improve without a compatibility
  change; they are not a matching interface. Details contain bounded
  identifiers and numeric limits. They never contain raw target output,
  observations, credentials, or exception text.
  """

  alias Wotex.Conformance.Pointer

  @phases [
    :input,
    :value,
    :limits,
    :claim,
    :vector,
    :subject,
    :corpus,
    :artifact,
    :target,
    :protocol,
    :result,
    :report,
    :environment,
    :runner
  ]

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, path: nil, details: %{}]

  @type phase ::
          :input
          | :value
          | :limits
          | :claim
          | :vector
          | :subject
          | :corpus
          | :artifact
          | :target
          | :protocol
          | :result
          | :report
          | :environment
          | :runner

  @type t :: %__MODULE__{
          code: atom(),
          phase: phase(),
          message: String.t(),
          path: String.t() | nil,
          details: map()
        }

  @doc "Returns the closed conformance error phase vocabulary."
  @spec phases() :: [phase(), ...]
  def phases, do: @phases

  @doc """
  Builds a structured error for one contract phase.

  Options are `:path`, a list of JSON Pointer segments addressing the rejected
  member, and `:details`, a bounded map of identifiers and limits. An empty or
  absent segment list records `nil`, meaning no single member is implicated.
  """
  @spec new(atom(), phase(), String.t(), keyword()) :: t()
  def new(code, phase, message, options \\ [])
      when is_atom(code) and phase in @phases and is_binary(message) and is_list(options) do
    %__MODULE__{
      code: code,
      phase: phase,
      message: message,
      path: path(Keyword.get(options, :path, [])),
      details: Keyword.get(options, :details, %{})
    }
  end

  defp path([]), do: nil
  defp path(nil), do: nil
  defp path(segments) when is_list(segments), do: Pointer.encode(segments)
end
