defmodule Wotex.Profiles.Draft do
  @moduledoc "Pure local-reference finalization of bounded consumer-owned profile drafts; no model facts are guessed."

  alias Wotex.Profiles.{
    AuthoringCandidate,
    Envelope,
    Error,
    Finalized,
    Finalizer,
    Grammar,
    ValidationReport
  }

  @doc "Resolves the exact included DAG and derives canonical bundle bytes without approval or activation."
  @spec finalize(term(), term()) ::
          {:ok, Finalized.t() | ValidationReport.t()} | {:error, Error.t()}
  def finalize(bytes, contract) do
    case AuthoringCandidate.prepare(bytes, contract, "draft", "not_supplied") do
      {:ok, data, contract, remaining} -> finalize(data, bytes, contract, remaining)
      {:report, report} -> {:ok, report}
      error -> error
    end
  end

  defp finalize(data, bytes, contract, remaining) do
    with {:ok, bundle, _} <- Finalizer.resolve(data, contract.data, remaining, true),
         {:ok, encoded} <- Envelope.encode(bundle),
         true <- byte_size(encoded) <= contract.data["limits"]["max_bundle_bytes"] do
      {:ok,
       %Finalized{
         bundle_bytes: encoded,
         draft_sha256: Grammar.hash(bytes),
         bundle_sha256: Grammar.hash(encoded),
         contract_sha256: contract.sha256
       }}
    else
      false ->
        Error.refusal(:input_limit)

      {:error, %Error{code: code}} = error
      when code in [:input_limit, :numeric_limit, :report_limit] ->
        error

      {:error, error} ->
        case AuthoringCandidate.invalid(bytes, contract, :semantic, error, "not_supplied") do
          {:report, report} -> {:ok, report}
          error -> error
        end
    end
  end
end
