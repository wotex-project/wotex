defmodule WotexContinuum.Failure do
  @moduledoc """
  Portable failure details embedded in result and receipt values.
  """

  alias WotexContinuum.{Error, Validation}

  @enforce_keys [:code, :message]
  defstruct [:code, :message, details: %{}]

  @type t :: %__MODULE__{code: String.t(), message: String.t(), details: term()}

  @doc "Constructs portable failure details."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
    with {:ok, data} <- Validation.normalize(data, [:code, :message, :details]),
         {:ok, code} <- Validation.required(data, :code),
         {:ok, code} <- Validation.string(code, ["code"], max: 256),
         {:ok, message} <- Validation.required(data, :message),
         {:ok, message} <- Validation.string(message, ["message"], max: 4_096),
         {:ok, details} <- Validation.json_value(Map.get(data, :details, %{}), ["details"]) do
      {:ok, %__MODULE__{code: code, message: message, details: details}}
    end
  end

  @doc "Returns the wire map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{"code" => value.code, "message" => value.message, "details" => value.details}
  end
end
