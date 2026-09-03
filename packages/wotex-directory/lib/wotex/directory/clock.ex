defmodule Wotex.Directory.Clock do
  @moduledoc """
  Consumer time port used for every registration and expiry decision.
  """

  @doc "Returns the consumer-owned current instant used by directory decisions."
  @callback now(state :: term()) :: {:ok, DateTime.t()} | {:error, term()}
end
