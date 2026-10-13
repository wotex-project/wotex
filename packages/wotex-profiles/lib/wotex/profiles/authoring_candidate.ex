defmodule Wotex.Profiles.AuthoringCandidate do
  @moduledoc false

  alias Wotex.Profiles.{Contract, Error, Parser, Shape, ValidationReport}

  @doc false
  @spec prepare(term(), term(), String.t(), String.t()) ::
          {:ok, map(), Contract.t(), non_neg_integer()}
          | {:report, ValidationReport.t()}
          | {:error, Error.t()}
  def prepare(bytes, contract, kind, capture) do
    with {:ok, contract} <- Contract.new(contract),
         true <- is_binary(bytes),
         true <- byte_size(bytes) <= contract.data["limits"]["max_bundle_bytes"] do
      parse(bytes, contract, kind, capture)
    else
      false ->
        if(is_binary(bytes), do: Error.refusal(:input_limit), else: Error.refusal(:invalid_input))

      error ->
        error
    end
  end

  defp parse(bytes, contract, kind, capture) do
    case Parser.decode(bytes, contract.data["limits"]["reader"]) do
      {:ok, data, _} -> shape(data, bytes, contract, kind, capture)
      {:error, %Error{code: code}} = error when code in [:input_limit, :numeric_limit] -> error
      {:error, error} -> invalid(bytes, contract, :syntax, error, capture)
    end
  end

  defp shape(data, bytes, contract, kind, capture) do
    limits = contract.data["limits"]

    case Shape.check(
           data,
           contract.data["schemas"][kind],
           limits["max_check_steps"],
           limits["max_diagnostics"]
         ) do
      {:ok, [], used, false} ->
        {:ok, data, contract, limits["max_check_steps"] - used}

      {:ok, errors, _, truncated} ->
        diagnostics =
          Enum.map(errors, fn error ->
            ValidationReport.failure(:shape, %Error{code: :invalid_input, path: error["path"]})
          end)

        case ValidationReport.build(bytes, contract, capture, diagnostics, truncated) do
          {:ok, report} -> {:report, report}
          error -> error
        end

      error ->
        error
    end
  end

  @doc false
  @spec invalid(binary(), Contract.t(), atom(), Error.t(), String.t()) ::
          {:report, ValidationReport.t()} | {:error, Error.t()}
  def invalid(bytes, contract, phase, error, capture) do
    case ValidationReport.build(
           bytes,
           contract,
           capture,
           [ValidationReport.failure(phase, error)],
           false
         ) do
      {:ok, report} -> {:report, report}
      error -> error
    end
  end
end
