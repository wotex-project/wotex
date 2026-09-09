defmodule Wotex.Thread.JoinerAdmission do
  @moduledoc "A finite, exact-identity Thread commissioner admission with a redacted PSKd."

  alias Wotex.Thread.{Error, JoinerIdentity}
  alias Wotex.Thread.OpenThread.CommissioningValue

  @derive {Inspect, only: [:identity, :lifetime]}
  @enforce_keys [:identity, :pskd, :lifetime]
  defstruct [:identity, :pskd, :lifetime]

  @type t :: %__MODULE__{identity: JoinerIdentity.t(), pskd: String.t(), lifetime: 1..3600}

  @doc "Validates an exact identity, PSKd and a lifetime in seconds, defaulting to 60."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{identity: identity, pskd: pskd} = input) when map_size(input) == 2,
    do: new(%{identity: identity, pskd: pskd, lifetime: 60})

  def new(%{identity: identity, pskd: pskd, lifetime: lifetime} = input)
      when map_size(input) == 3 and is_integer(lifetime) and lifetime in 1..3600 do
    with {:ok, identity} <- normalized_identity(identity), true <- CommissioningValue.pskd?(pskd) do
      {:ok, %__MODULE__{identity: identity, pskd: pskd, lifetime: lifetime}}
    else
      _ -> {:error, Error.new(:invalid_joiner_admission)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_joiner_admission)}

  @doc false
  @spec parameters(term()) :: {:ok, map()} | {:error, Error.t()}
  def parameters(%__MODULE__{} = admission), do: encode(admission)

  def parameters(input) do
    with {:ok, admission} <- new(input), do: encode(admission)
  end

  defp normalized_identity(%JoinerIdentity{} = identity) do
    with {:ok, _} <- JoinerIdentity.encode(identity), do: {:ok, identity}
  end

  defp normalized_identity(input), do: JoinerIdentity.new(input)

  @doc false
  @spec encode(term()) :: {:ok, map()} | {:error, Error.t()}
  def encode(%__MODULE__{} = admission) when map_size(admission) == 4 do
    with {:ok, valid} <- new(Map.from_struct(admission)),
         {:ok, identity} <- JoinerIdentity.encode(valid.identity),
         do: {:ok, %{identity: identity, pskd: valid.pskd, lifetime: valid.lifetime}}
  end

  def encode(_), do: {:error, Error.new(:invalid_joiner_admission)}
end
