defmodule Wotex.Runtime.Implementation.Inputs do
  @moduledoc "Explicit current registration, verification, trust, policy, target and UTC observation."
  alias Wotex.Runtime.Implementation.{
    Error,
    Grammar,
    Policy,
    Record,
    Registration,
    Trust,
    Verification
  }

  @fields [
    :registrations,
    :verification,
    :trust,
    :policy,
    :target,
    :apis,
    :bindings,
    :now_ms,
    :scope
  ]
  @type t :: %__MODULE__{
          registrations: %{String.t() => Registration.t()},
          verification: Verification.t() | nil,
          trust: Trust.t(),
          policy: Policy.t(),
          target: String.t(),
          apis: [map()],
          bindings: [map()],
          now_ms: non_neg_integer(),
          scope: String.t()
        }
  defstruct @fields

  @doc "Revalidates every explicit input; no ambient defaults or discovery are used."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(value) do
    if Grammar.closed?(value, @fields) and registrations?(value.registrations) and
         verification?(value.verification) and valid_record?(value.trust, Trust) and
         valid_record?(value.policy, Policy) and Grammar.token?(value.target) and
         Grammar.token?(value.scope) and Grammar.tuples?(value.apis) and
         Grammar.tuples?(value.bindings) and Grammar.time?(value.now_ms) do
      {:ok, struct(__MODULE__, value)}
    else
      {:error, Error.new(:invalid_admission_inputs, :construction, %{})}
    end
  end

  @doc false
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(%__MODULE__{} = value), do: new(Map.from_struct(value))
  def validate(_), do: {:error, Error.new(:invalid_admission_inputs, :construction, %{})}

  defp registrations?(value) do
    is_map(value) and not is_struct(value) and map_size(value) <= 64 and
      Enum.all?(value, fn {id, registration} ->
        case Record.validate(registration, Registration) do
          {:ok, record} -> id == record["id"]
          _ -> false
        end
      end)
  end

  defp verification?(nil), do: true
  defp verification?(value), do: valid_record?(value, Verification)
  defp valid_record?(value, module), do: match?({:ok, _}, Record.validate(value, module))
end
