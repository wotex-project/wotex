defmodule Wotex.Binding.HTTP.Error do
  @moduledoc "Structured, credential-free HTTP binding failure."

  @type phase ::
          :configuration
          | :form
          | :request
          | :response
          | :codec
          | :client
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
