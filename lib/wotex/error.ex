defmodule Wotex.Error do
  @moduledoc """
  Structured failure returned by Wotex public operations.

  Match on `code`, `phase`, and `path`. Human-readable messages may improve in
  compatible releases and are not a matching interface.
  """

  @type phase :: :parse | :value | :schema | :semantic | :encode
  @type t :: %__MODULE__{
          code: atom(),
          phase: phase(),
          path: String.t(),
          message: String.t(),
          details: map()
        }

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, path: "/", details: %{}]

  @doc false
  @spec new(atom(), phase(), String.t(), String.t(), map()) :: t()
  def new(code, phase, message, path \\ "/", details \\ %{})
      when is_atom(code) and is_atom(phase) and is_binary(message) and is_binary(path) and
             is_map(details) do
    %__MODULE__{code: code, phase: phase, message: message, path: path, details: details}
  end
end
