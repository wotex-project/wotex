defmodule Wotex.Runtime.Implementation.InstanceKey do
  @moduledoc "Consumer-assigned scope, instance and generation; construction allocates no identity."
  alias Wotex.Runtime.Implementation.{Error, Grammar}

  @type t :: %__MODULE__{
          consumer_scope: String.t(),
          instance_id: String.t(),
          generation: pos_integer()
        }
  defstruct [:consumer_scope, :instance_id, :generation]

  @doc "Validates the closed consumer identity map."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(value) do
    if Grammar.closed?(value, [:consumer_scope, :instance_id, :generation]) and
         Grammar.token?(value.consumer_scope) and Grammar.token?(value.instance_id) and
         Grammar.time?(value.generation) and value.generation > 0 do
      {:ok, struct(__MODULE__, value)}
    else
      {:error, Error.new(:invalid_instance, :construction, %{})}
    end
  end

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = key), do: new(Map.from_struct(key)) == {:ok, key}
  def valid?(_), do: false
end
