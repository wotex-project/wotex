defmodule Wotex.Profiles.Validation do
  @moduledoc "One shared deterministic profile-bundle validator for authoring, CI, import and explicit capture checks."

  alias Wotex.Profiles.{AuthoringCandidate, Compiler, Error, Finalizer, ValidationReport}

  @doc "Checks bundle shape, exact closure and installed mechanics, then optional supplied capture; never grants admission."
  @spec check(term(), term(), term()) :: {:ok, ValidationReport.t()} | {:error, Error.t()}
  def check(bytes, contract, capture) do
    status = if capture == nil, do: "not_supplied", else: "not_checked"

    case AuthoringCandidate.prepare(bytes, contract, "bundle", status) do
      {:ok, data, contract, remaining} ->
        semantics(data, bytes, contract, capture, status, remaining)

      {:report, report} ->
        {:ok, report}

      error ->
        error
    end
  end

  defp semantics(data, bytes, contract, capture, status, remaining) do
    case Finalizer.resolve(data, contract.data, remaining, false) do
      {:ok, bundle, _} -> bindings(bundle, bytes, contract, capture, status)
      error -> failure(error, bytes, contract, :semantic, status)
    end
  end

  defp bindings(bundle, bytes, contract, capture, status) do
    closure = %{
      "definitions" => bundle["definitions"],
      "bindings" => contract.data["bindings"],
      "contracts" => contract.data["contracts"]
    }

    limits = contract.data["limits"]["reader"]

    case Compiler.check(bundle["profile"], closure, limits) do
      {:ok, _} -> capture(bundle, closure, bytes, contract, capture, status, limits)
      error -> failure(error, bytes, contract, :binding, status)
    end
  end

  defp capture(_, _, bytes, contract, nil, _, _),
    do: ValidationReport.build(bytes, contract, "not_supplied", [], false)

  defp capture(bundle, closure, bytes, contract, capture, _, limits) do
    case Compiler.compile(bundle["profile"], closure, capture, limits) do
      {:ok, _} -> ValidationReport.build(bytes, contract, "matched", [], false)
      error -> failure(error, bytes, contract, :capture, "mismatch")
    end
  end

  defp failure({:error, %Error{code: code}} = error, _, _, _, _)
       when code in [:input_limit, :numeric_limit, :report_limit], do: error

  defp failure({:error, error}, bytes, contract, phase, status) do
    case AuthoringCandidate.invalid(bytes, contract, phase, error, status) do
      {:report, report} -> {:ok, report}
      error -> error
    end
  end
end
