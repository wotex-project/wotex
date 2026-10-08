defmodule Wotex.Runtime.Codec.Result do
  @moduledoc """
  Inert decoded tree correlated to an exact implementation and request.

  Identity is derived from the validated Call, never decoder output. Inspection
  omits the tree; consumers decide whether to retain sensitive decoded values.
  """
  alias Wotex.Runtime.Codec.{Call, Value}
  alias Wotex.Runtime.Implementation.{Error, Grammar}

  @fields [
    :value,
    :descriptor_sha256,
    :deployment,
    :contract_id,
    :contract_sha256,
    :configuration_sha256,
    :binding,
    :instance_key,
    :request_id
  ]
  @derive {Inspect, except: [:value]}
  @type t :: %__MODULE__{
          value: map(),
          descriptor_sha256: String.t(),
          deployment: map(),
          contract_id: String.t(),
          contract_sha256: String.t(),
          configuration_sha256: String.t(),
          binding: map(),
          instance_key: Wotex.Runtime.Implementation.InstanceKey.t(),
          request_id: String.t()
        }
  defstruct @fields

  @doc "Validates the typed tree and derives all identities from Call."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(value, call) do
    with :ok <- Call.validate(call),
         {:ok, value} <- Value.validate(value) do
      plan = call.plan
      contract = plan.admission.registration.value["codec_contract"]

      {:ok,
       %__MODULE__{
         value: value,
         descriptor_sha256: plan.admission.descriptor.sha256,
         deployment: plan.admission.value["deployment"],
         contract_id: contract["id"],
         contract_sha256: contract["sha256"],
         configuration_sha256: plan.configuration_sha256,
         binding: plan.admission.descriptor.value["binding"],
         instance_key: plan.instance_key,
         request_id: call.context.request_id
       }}
    end
  end

  @doc false
  @spec validate(term(), term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = result, call) do
    with true <- Grammar.closed?(Map.from_struct(result), @fields),
         {:ok, ^result} <- new(result.value, call) do
      :ok
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:correlation_failed, :output, %{})}
    end
  end

  def validate(_, _), do: {:error, Error.new(:protocol_fault, :output, %{})}
end
