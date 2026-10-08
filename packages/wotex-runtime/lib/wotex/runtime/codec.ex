defmodule Wotex.Runtime.Codec do
  @moduledoc """
  Explicit bounded decoding into inert, implementation-correlated values.

  The caller supplies an executor; descriptors never select a module. Validation
  precedes exactly one callback. No retry, fallback or child startup is implicit.
  """
  alias Wotex.Runtime.Codec.{Call, Grammar, Result}
  alias Wotex.Runtime.Implementation.Error

  @doc "Admits bytes and metadata, calls the supplied executor once and revalidates its result."
  @spec decode(term(), term(), term(), term(), term()) :: {:ok, Result.t()} | {:error, Error.t()}
  def decode(plan, input, metadata, context, executor) do
    with {:ok, call} <- Call.new(plan, context),
         :ok <- input(input),
         true <- Grammar.flat?(metadata),
         {:ok, result} <- execute(executor, input, metadata, call),
         :ok <- result(result, call) do
      {:ok, result}
    else
      {:error, %Error{}} = error -> error
      _ -> failure(:invalid_metadata, :admission)
    end
  end

  defp input(value) when is_binary(value) and byte_size(value) <= 65_536, do: :ok
  defp input(_), do: failure(:invalid_input, :admission)

  defp result(result, call) do
    case Result.validate(result, call) do
      :ok -> :ok
      {:error, %Error{code: :correlation_failed}} = error -> error
      _ -> failure(:protocol_fault, :output)
    end
  end

  defp execute({module, config}, input, metadata, call) when is_atom(module) do
    try do
      case module.decode(input, metadata, call, config) do
        {:ok, %Result{} = result} ->
          {:ok, result}

        {:error, %Error{} = error} ->
          if Error.valid?(error), do: {:error, error}, else: failure(:protocol_fault, :decode)

        _ ->
          failure(:protocol_fault, :decode)
      end
    rescue
      _ -> failure(:codec_unavailable, :decode)
    catch
      _, _ -> failure(:codec_unavailable, :decode)
    end
  end

  defp execute(_, _, _, _), do: failure(:protocol_fault, :admission)
  defp failure(code, phase), do: {:error, Error.new(code, phase, %{})}
end
