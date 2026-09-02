defmodule Wotex.Conformance.Error do
  @moduledoc """
  Stable error returned when a conformance contract cannot be constructed or
  an external target cannot be exercised safely.

  Error details contain bounded identifiers and numeric limits. They never
  contain raw target output, observations, credentials, or exception text.
  """

  @enforce_keys [:code, :message]
  defexception [:code, :message, path: [], details: %{}]

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          path: [String.t() | non_neg_integer()],
          details: map()
        }

  @doc false
  @spec new(atom(), String.t(), keyword()) :: t()
  def new(code, message, options \\ []) when is_atom(code) and is_binary(message) do
    %__MODULE__{
      code: code,
      message: message,
      path: Keyword.get(options, :path, []),
      details: Keyword.get(options, :details, %{})
    }
  end
end
