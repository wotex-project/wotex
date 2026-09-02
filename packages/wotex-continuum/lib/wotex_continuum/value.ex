defmodule WotexContinuum.Value do
  @moduledoc """
  Behaviour implemented by every registered continuum value.
  """

  @callback kind() :: String.t()
  @callback new(map()) :: {:ok, struct()} | {:error, WotexContinuum.Error.t()}
  @callback to_map(struct()) :: map()
end
