defmodule Wotex.Matter.RuntimeRelay.Frame do
  @moduledoc false

  alias Wotex.Matter.Error

  @derive {Inspect, only: [:generation]}
  @enforce_keys [:pid, :generation, :token, :value]
  defstruct [:pid, :generation, :token, :value]

  @opaque t :: %__MODULE__{
            pid: pid(),
            generation: binary(),
            token: reference(),
            value: {:value, term(), map()} | {:error, Error.t()}
          }
end
