defmodule Wotex.Runtime.Implementation.Plan do
  @moduledoc """
  Passive admitted implementation, schema-validated configuration and instance.

  The explicitly supplied schema validator runs once on bounded immutable data.
  It must be pure. Exceptions and malformed returns become fixed refusals.
  """
  alias Wotex.Runtime.Implementation.{Admission, Error, InstanceKey, JSON}

  @type t :: %__MODULE__{
          admission: Admission.t(),
          configuration: map(),
          configuration_sha256: String.t(),
          instance_key: InstanceKey.t(),
          sha256: String.t()
        }
  defstruct [:admission, :configuration, :configuration_sha256, :instance_key, :sha256]

  @doc "Binds admitted configuration to the exact consumer scope and generation."
  @spec new(term(), term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(admission, configuration, instance_key, validator) do
    with :ok <- Admission.validate(admission),
         true <-
           InstanceKey.valid?(instance_key) and
             instance_key.consumer_scope == admission.value["scope"],
         true <- is_map(configuration) and not is_struct(configuration),
         {:ok, digest} <- JSON.digest(configuration),
         :ok <-
           validate_schema(
             validator,
             configuration,
             admission.descriptor.value["configuration_schema"]
           ) do
      plan = %__MODULE__{
        admission: admission,
        configuration: configuration,
        configuration_sha256: digest,
        instance_key: instance_key
      }

      {:ok, %{plan | sha256: identity(plan)}}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_configuration, :construction, %{})}
    end
  end

  @doc false
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = plan) do
    with true <-
           Map.keys(Map.from_struct(plan)) |> Enum.sort() ==
             Enum.sort([:admission, :configuration, :configuration_sha256, :instance_key, :sha256]),
         :ok <- Admission.validate(plan.admission),
         true <-
           InstanceKey.valid?(plan.instance_key) and
             plan.instance_key.consumer_scope == plan.admission.value["scope"],
         true <- is_map(plan.configuration) and not is_struct(plan.configuration),
         {:ok, digest} <- JSON.digest(plan.configuration),
         true <- digest == plan.configuration_sha256 and identity(plan) == plan.sha256 do
      :ok
    else
      _ -> {:error, Error.new(:invalid_configuration, :construction, %{})}
    end
  end

  def validate(_), do: {:error, Error.new(:invalid_configuration, :construction, %{})}

  defp identity(plan) do
    {:ok, digest} =
      JSON.digest(%{
        "admission_sha256" => plan.admission.sha256,
        "configuration_sha256" => plan.configuration_sha256,
        "consumer_scope" => plan.instance_key.consumer_scope,
        "instance_id" => plan.instance_key.instance_id,
        "generation" => plan.instance_key.generation
      })

    digest
  end

  defp validate_schema(validator, config, schema) when is_function(validator, 2) do
    try do
      if validator.(config, schema) == :ok, do: :ok, else: {:error, :invalid_configuration}
    rescue
      _ -> {:error, :invalid_configuration}
    catch
      _, _ -> {:error, :invalid_configuration}
    end
  end

  defp validate_schema(_, _, _), do: {:error, :invalid_configuration}
end
