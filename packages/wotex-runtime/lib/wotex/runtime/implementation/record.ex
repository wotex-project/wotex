defmodule Wotex.Runtime.Implementation.Record do
  @moduledoc false

  alias Wotex.Runtime.Implementation.{
    Descriptor,
    Error,
    Grammar,
    JSON,
    Policy,
    Registration,
    Trust,
    Verification
  }

  @doc false
  @spec new(module(), term()) :: {:ok, struct()} | {:error, Error.t()}
  def new(module, value) do
    with {:ok, digest} <- JSON.digest(value),
         true <- grammar(module, value) do
      {:ok, struct(module, value: value, sha256: digest)}
    else
      {:error, :limit_exceeded} -> {:error, Error.new(:limit_exceeded, :construction, %{})}
      _ -> {:error, Error.new(code(module), :construction, %{})}
    end
  end

  @doc false
  @spec validate(term(), module()) :: {:ok, map()} | {:error, Error.t()}
  def validate(%{__struct__: module, value: value} = record, module) do
    with {:ok, rebuilt} <- new(module, value),
         true <- rebuilt == record do
      {:ok, value}
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:identity_mismatch, :construction, %{})}
    end
  end

  def validate(_, _), do: {:error, Error.new(:invalid_admission_inputs, :construction, %{})}

  defp grammar(Descriptor, value), do: Grammar.descriptor?(value)
  defp grammar(Registration, value), do: Grammar.registration?(value)
  defp grammar(Verification, value), do: Grammar.verification?(value)
  defp grammar(Trust, value), do: Grammar.trust?(value)
  defp grammar(Policy, value), do: Grammar.policy?(value)
  defp code(Descriptor), do: :invalid_descriptor
  defp code(_), do: :invalid_admission_inputs
end
