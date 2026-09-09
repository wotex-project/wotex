defmodule Wotex.Conformance.Target.Response do
  @moduledoc """
  Validated observation or unsupported outcome from a target adapter.

  This value cannot represent pass or fail; classification remains runner
  authority.

  `from_map/2` validates protocol name and version, correlates the vector
  identifier with the request, and accepts either an observed JSON value or an
  explicit unsupported outcome. An unsupported response must omit `actual`.
  Diagnostic codes are bounded, deduplicated, and sorted before the value is
  returned.

  The external target protocol never carries the runner-owned expectation.
  This struct records only what the adapter observed or declined to implement.
  `Wotex.Conformance.Runner` compares an observation with the expectation and
  assigns pass or fail. A syntactically valid response is therefore not itself
  evidence that the subject satisfies a claim.
  """

  alias Wotex.Conformance.{Error, Input, Value}

  @enforce_keys [:vector_id, :outcome, :codes]
  defstruct [:vector_id, :outcome, :actual, :codes]

  @type t :: %__MODULE__{
          vector_id: String.t(),
          outcome: :observed | :unsupported,
          actual: Value.json_value() | nil,
          codes: [String.t()]
        }

  @doc "Validates a target response against the vector ID from its request."
  @spec from_map(map(), String.t()) :: {:ok, t()} | {:error, Error.t()}
  def from_map(input, expected_vector_id) when is_map(input) do
    with :ok <-
           Input.only_keys(
             input,
             ~w(protocol protocol_version vector_id outcome actual codes)
           ),
         :ok <- validate_protocol(input),
         {:ok, vector_id} <- validate_vector_id(input, expected_vector_id),
         {:ok, outcome} <- validate_outcome(Map.get(input, "outcome")),
         {:ok, actual} <- validate_actual(outcome, input),
         {:ok, codes} <- validate_codes(Map.get(input, "codes", [])) do
      {:ok, %__MODULE__{vector_id: vector_id, outcome: outcome, actual: actual, codes: codes}}
    end
  end

  def from_map(_, _) do
    {:error, Error.new(:invalid_target_response, :protocol, "target response must be an object")}
  end

  @doc "Alias for `from_map/2`, the map-shaped target response constructor."
  @spec new(map(), String.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, expected_vector_id), do: from_map(input, expected_vector_id)

  defp validate_protocol(%{
         "protocol" => "wotex.conformance.target",
         "protocol_version" => "1.0"
       }),
       do: :ok

  defp validate_protocol(_) do
    {:error,
     Error.new(:target_protocol_mismatch, :protocol, "target response protocol is not supported")}
  end

  defp validate_vector_id(input, expected) do
    case Map.get(input, "vector_id") do
      ^expected ->
        {:ok, expected}

      _ ->
        {:error,
         Error.new(
           :target_vector_mismatch,
           :protocol,
           "target response vector ID does not match request"
         )}
    end
  end

  defp validate_outcome("observed"), do: {:ok, :observed}
  defp validate_outcome("unsupported"), do: {:ok, :unsupported}

  defp validate_outcome(_) do
    {:error,
     Error.new(:invalid_target_outcome, :protocol, "target response outcome is not supported")}
  end

  defp validate_actual(:observed, %{"actual" => actual}), do: Value.validate(actual)

  defp validate_actual(:observed, _) do
    {:error,
     Error.new(:missing_target_observation, :protocol, "observed target response requires actual")}
  end

  defp validate_actual(:unsupported, input) do
    if Map.has_key?(input, "actual") do
      {:error,
       Error.new(
         :unexpected_target_observation,
         :protocol,
         "unsupported target response must omit actual"
       )}
    else
      {:ok, nil}
    end
  end

  defp validate_codes(codes) when is_list(codes) and length(codes) <= 16 do
    codes
    |> Enum.reduce_while({:ok, []}, fn code, {:ok, valid} ->
      case Value.validate_identifier(code, "codes", max_bytes: 128) do
        {:ok, code} -> {:cont, {:ok, [code | valid]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> then(fn
      {:ok, valid} -> {:ok, valid |> Enum.uniq() |> Enum.sort()}
      {:error, error} -> {:error, error}
    end)
  end

  defp validate_codes(_) do
    {:error,
     Error.new(:invalid_target_codes, :protocol, "target response codes must be a bounded list")}
  end
end
