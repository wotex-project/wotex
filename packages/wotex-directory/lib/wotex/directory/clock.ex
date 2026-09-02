defmodule Wotex.Directory.Clock do
  @moduledoc """
  Consumer time port used for every registration and expiry decision.
  """

  @callback now(state :: term()) :: {:ok, DateTime.t()} | {:error, term()}
end
