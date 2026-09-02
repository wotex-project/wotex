defmodule Wotex.Runtime.Error do
  @moduledoc """
  Stable runtime failure.

  Match on `code` and `phase`. Messages may improve in compatible releases.
  External return values are deliberately not copied into errors because they
  can contain credential or transport internals.
  """

  @type phase ::
          :construction
          | :selection
          | :credentials
          | :transport
          | :dispatch
          | :subscription

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
