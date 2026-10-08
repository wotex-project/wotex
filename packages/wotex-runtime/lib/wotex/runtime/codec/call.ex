defmodule Wotex.Runtime.Codec.Call do
  @moduledoc """
  Validated admitted codec Plan and caller Context.

  Construction is pure. The executor still revalidates current admission and
  observes the original deadline immediately before dispatch and reply admission.
  Inspection excludes configuration and context metadata.
  """
  alias Wotex.Runtime.Codec.Grammar, as: CodecGrammar
  alias Wotex.Runtime.Context
  alias Wotex.Runtime.Implementation.{Error, Grammar, Plan}

  @derive {Inspect, except: [:plan, :context]}
  @type t :: %__MODULE__{plan: Plan.t(), context: Context.t()}
  defstruct [:plan, :context]

  @doc "Checks the exact codec API, registration, stateless profile and configuration."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(plan, context) do
    with :ok <- Plan.validate(plan),
         :ok <- profile(plan),
         true <- CodecGrammar.flat?(plan.configuration),
         true <- context?(context) do
      {:ok, %__MODULE__{plan: plan, context: context}}
    else
      {:error, %Error{}} = error -> error
      _ -> failure(:invalid_configuration)
    end
  end

  @doc false
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = call) do
    with true <- Grammar.closed?(Map.from_struct(call), [:plan, :context]),
         {:ok, ^call} <- new(call.plan, call.context) do
      :ok
    else
      {:error, %Error{}} = error -> error
      _ -> failure(:invalid_configuration)
    end
  end

  def validate(_), do: failure(:invalid_configuration)

  defp profile(plan) do
    d = plan.admission.descriptor.value
    r = plan.admission.registration.value

    cond do
      d["kind"] != "codec" or d["api"] != %{"id" => "wotex.codec", "version" => "1.0.0"} ->
        failure(:incompatible_api)

      d["binding"] not in [
        %{"id" => "beam-codec", "version" => "1.0.0"},
        %{"id" => "process-codec", "version" => "1.0.0"}
      ] ->
        failure(:incompatible_binding)

      d["configuration_schema"] != r["configuration_schema"] or is_nil(r["codec_contract"]) ->
        failure(:schema_mismatch)

      d["support"] != [] or d["permissions"] != [] or
          d["state"] != %{
            "scope" => "stateless",
            "continuity" => "none",
            "update_mode" => "message_boundary",
            "format" => nil
          } ->
        failure(:unsupported_cell)

      plan.admission.value["limits"]["request_ms"] == 0 or
          plan.admission.value["limits"]["inflight"] == 0 ->
        failure(:enforcement_unavailable)

      true ->
        :ok
    end
  end

  defp context?(%Context{} = context) do
    Grammar.closed?(Map.from_struct(context), [:request_id, :deadline, :metadata]) and
      match?({:ok, ^context}, Context.new(Map.to_list(Map.from_struct(context)))) and
      deadline?(context.deadline)
  end

  defp context?(_), do: false

  defp deadline?(%DateTime{} = value) do
    try do
      DateTime.to_unix(value, :millisecond)
      true
    rescue
      _ -> false
    end
  end

  defp deadline?(value), do: is_nil(value) or is_integer(value)
  defp failure(code), do: {:error, Error.new(code, :admission, %{})}
end
