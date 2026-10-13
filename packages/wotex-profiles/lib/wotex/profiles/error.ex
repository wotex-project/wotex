defmodule Wotex.Profiles.Error do
  @moduledoc "Fixed, payload-free refusal from an external-profile boundary."
  @enforce_keys [:code, :path]
  defstruct [:code, :path]
  @type t :: %__MODULE__{code: atom(), path: String.t()}

  @doc "Returns only an installed code and pointer, without the input or foreign exception."
  @spec refusal(atom(), String.t()) :: {:error, t()}
  def refusal(code, path \\ ""), do: {:error, %__MODULE__{code: code, path: path}}
end
