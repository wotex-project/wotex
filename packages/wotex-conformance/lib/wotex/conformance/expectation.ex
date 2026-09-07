defmodule Wotex.Conformance.Expectation do
  @moduledoc """
  Runner-owned expected value for a conformance vector.

  Revision 1.0 supports exact canonical equality. Expectations are never sent
  through the external target protocol.
  """

  alias Wotex.Conformance.{Canonical, Error, Input, Value}

  @enforce_keys [:operator, :value, :digest]
  defstruct [:operator, :value, :digest]

  @type t :: %__MODULE__{operator: :exact, value: Value.json_value(), digest: String.t()}

  @doc "Constructs an exact-match expectation from decoded vector data."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_map(input) when is_map(input) do
    with :ok <- Input.only_keys(input, ~w(operator value)),
         {:ok, operator_input} <- Input.required(input, :operator),
         {:ok, operator} <- validate_operator(operator_input),
         {:ok, value} <- Input.required(input, :value),
         {:ok, validated} <- Value.validate(value),
         {:ok, digest} <- Canonical.digest(validated) do
      {:ok, %__MODULE__{operator: operator, value: validated, digest: digest}}
    end
  end

  def from_map(_input),
    do: {:error, Error.new(:invalid_type, :vector, "expectation must be an object")}

  @doc "Alias for `from_map/1`, the map-shaped expectation constructor."
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(input), do: from_map(input)

  @doc "Serializes the expectation without exposing its derived digest."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = expectation) do
    %{
      "operator" => Atom.to_string(expectation.operator),
      "value" => expectation.value
    }
  end

  defp validate_operator("exact"), do: {:ok, :exact}
  defp validate_operator(:exact), do: {:ok, :exact}

  defp validate_operator(_operator) do
    {:error,
     Error.new(:unsupported_operator, :vector, "expectation operator is not supported",
       path: ["operator"]
     )}
  end
end
