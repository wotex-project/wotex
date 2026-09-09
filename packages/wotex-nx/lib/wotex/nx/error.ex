defmodule Wotex.Nx.Error do
  @moduledoc """
  Structured failures returned at the Wotex-to-Nx boundary.

  Stable `code` and `phase` values support programmatic handling while
  `message` and `details` explain the rejected contract. Errors represent
  expected invalid input and are returned in tagged tuples by public APIs.

  Phases distinguish construction, window selection, encoding, unit
  conversion, output decoding, and resource-limit rejection. The details map
  may carry values such as expected and actual shapes, field names, or
  configured ceilings. Consumers should branch on `code` and `phase`; message
  text is explanatory and is not a compatibility surface.

  These errors describe data and numerical-contract failures. They do not
  confer retry policy, authorize an effect, or replace exceptions raised by an
  unexpected dependency or programming fault.
  """

  @typedoc "The stage at which a numerical contract was rejected."
  @type phase :: :construction | :window | :encoding | :unit | :output | :limit

  @typedoc "A stable error code, processing phase, readable message, and structured details."
  @type t :: %__MODULE__{
          code: atom(),
          phase: phase(),
          message: String.t(),
          details: map()
        }

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, details: %{}]

  @doc false
  @spec new(atom(), phase(), String.t(), map()) :: t()
  def new(code, phase, message, details \\ %{})
      when is_atom(code) and is_atom(phase) and is_binary(message) and is_map(details) do
    %__MODULE__{code: code, phase: phase, message: message, details: details}
  end
end
