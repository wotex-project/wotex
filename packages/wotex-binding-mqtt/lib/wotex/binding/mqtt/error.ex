defmodule Wotex.Binding.MQTT.Error do
  @moduledoc """
  Stable, credential-free MQTT binding failure.

  Match on `code`, `phase`, and `class`. Messages can improve in compatible
  releases. External client return values are never copied into this value.

  `class` is the retry classification the Runtime copies into its own error
  cause for `Wotex.Runtime.Retry`: `:timeout` marks an exhausted request
  budget, `:unavailable` marks a failed or raising client port call,
  `:protocol` marks a rejected MQTT, mapping, or codec value, and `:permanent`
  marks consumer configuration that no retry can repair. The class states how a
  failure was produced; it never authorizes a repeated Action.
  """

  @type phase :: :broker | :topic | :codec | :command | :mapping | :configuration | :client
  @type class :: :timeout | :unavailable | :rate_limited | :protocol | :permanent | nil

  @type t :: %__MODULE__{
          code: atom(),
          phase: phase(),
          class: class(),
          message: String.t(),
          details: map()
        }

  @classes [:timeout, :unavailable, :rate_limited, :protocol, :permanent, nil]

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, class: nil, details: %{}]

  @doc false
  @spec new(atom(), phase(), class(), String.t(), map()) :: t()
  def new(code, phase, class, message, details \\ %{})
      when is_atom(code) and is_atom(phase) and class in @classes and is_binary(message) and
             is_map(details) do
    %__MODULE__{code: code, phase: phase, class: class, message: message, details: details}
  end

  @doc "Returns the retry classification, `nil` when the failure is unclassified."
  @spec class(t()) :: class()
  def class(%__MODULE__{class: class}), do: class
end
