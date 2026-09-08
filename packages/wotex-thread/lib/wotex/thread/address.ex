defmodule Wotex.Thread.Address do
  @moduledoc "Read-only OpenThread management targets; application operations remain with their binding."
  alias Wotex.Thread.Error

  @doc "Allows only the explicit read-only daemon operation set."
  @spec validate_message(map()) :: :ok | {:error, Error.t()}
  def validate_message(%{type: type}) when type in [:state, :version, :network_name, :rloc16],
    do: :ok

  def validate_message(_), do: {:error, Error.new(:unsupported_operation)}
end
