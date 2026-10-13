defmodule Wotex.Routines.Error do
  @moduledoc "Payload-free refusal at an explicit routine value boundary."

  @enforce_keys [:code, :path]
  defstruct [:code, :path]

  @type t :: %__MODULE__{code: atom(), path: String.t()}

  @doc "Constructs a fixed refusal without retaining caller data."
  @spec refusal(atom(), String.t()) :: {:error, t()}
  def refusal(code, path \\ ""), do: {:error, %__MODULE__{code: code, path: path}}
end
