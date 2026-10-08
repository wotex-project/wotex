defmodule Wotex.Runtime.Codec.Executor do
  @moduledoc """
  Explicit consumer execution port for an admitted bounded codec.

  The executor owns current-admission revalidation, deadline observations and
  worker or native-host custody. It enforces the registered contract and returns
  a correlated Result. Neither the facade nor this behaviour starts a host.
  """
  alias Wotex.Runtime.Codec.{Call, Result}
  alias Wotex.Runtime.Implementation.Error
  @doc "Executes one admitted decode under the original deadline and generation."
  @callback decode(binary(), map(), Call.t(), term()) :: {:ok, Result.t()} | {:error, Error.t()}
end
