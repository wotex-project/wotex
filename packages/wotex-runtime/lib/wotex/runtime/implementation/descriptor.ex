defmodule Wotex.Runtime.Implementation.Descriptor do
  @moduledoc """
  Bounded optional implementation metadata, with an integer-only JCS identity.

  Parsing does not install, trust, authorize or start an implementation. All
  members are required; only namespaced `extensions` admit additional fields.
  """
  alias Wotex.Runtime.Implementation.{Error, JSON, Record}
  @type t :: %__MODULE__{value: map(), sha256: String.t()}
  defstruct [:value, :sha256]

  @doc "Parses a closed descriptor, rejecting duplicates and over-bound allocation."
  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(input) do
    with {:ok, value} <- JSON.decode(input),
         :ok <- schema(value),
         {:ok, descriptor} <- Record.new(__MODULE__, value) do
      {:ok, descriptor}
    else
      {:error, %Error{} = error} -> {:error, %{error | phase: :parse}}
      {:error, code} -> {:error, Error.new(code, :parse, %{})}
    end
  end

  @doc "Returns the complete map after revalidating grammar and identity."
  @spec to_map(term()) :: map() | {:error, Error.t()}
  def to_map(descriptor) do
    case Record.validate(descriptor, __MODULE__) do
      {:ok, value} -> value
      {:error, _} = error -> error
    end
  end

  defp schema(%{"schema" => "wotex.implementation@1"}), do: :ok
  defp schema(%{"schema" => _}), do: {:error, :unsupported_schema}
  defp schema(_), do: {:error, :invalid_descriptor}
end
