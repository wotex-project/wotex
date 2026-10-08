defmodule Wotex.Modbus.RegisterCodec.Host.Configuration do
  @moduledoc false

  alias Wotex.Modbus.RegisterCodec
  alias Wotex.Runtime.Codec.Call
  alias Wotex.Runtime.Context
  alias Wotex.Runtime.Implementation.{Admission, Error}

  @keys [:plan, :context, :driver, :current_inputs, :now, :owner]
  @guarantees ~w(deadline descendants immutable_deployment memory privileges)
  @ceilings %{
    "startup_ms" => 5000,
    "request_ms" => 1000,
    "shutdown_ms" => 1000,
    "inflight" => 1,
    "queued" => 0,
    "frame_bytes" => 131_072,
    "queue_bytes" => 262_144,
    "stderr_bytes" => 4096,
    "memory_bytes" => 67_108_864
  }
  @failures ~w(artifact_unverified enforcement_unavailable startup_failed codec_unavailable overloaded cleanup_unconfirmed)a
  @derive {Inspect, only: [:driver_pid, :limits]}
  @type t :: %__MODULE__{value: map(), driver_pid: pid(), limits: map()}
  defstruct [:value, :driver_pid, :limits]

  @doc false
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = config) do
    with true <- map_size(config) == 4,
         {:ok, ^config} <- build(config.value) do
      {:ok, config}
    else
      _ -> failure(:invalid_configuration)
    end
  end

  def new(value), do: build(value)

  defp build(value) do
    with true <- closed?(value, @keys),
         {:ok, _} <- Call.new(value.plan, value.context),
         :ok <- process_binding(value.plan),
         :ok <-
           RegisterCodec.validate_configuration(
             value.plan.configuration,
             RegisterCodec.configuration_schema()
           ),
         true <-
           local?(value.owner) and is_function(value.current_inputs, 0) and
             is_function(value.now, 0),
         {module, driver_config} when is_atom(module) <- value.driver,
         true <-
           Code.ensure_loaded?(module) and
             Enum.all?([profile: 1, open: 6, write: 3, close: 3], fn {f, a} ->
               function_exported?(module, f, a)
             end),
         {:ok, profile} <- invoke(fn -> module.profile(driver_config) end),
         true <- closed?(profile, [:pid, :artifact, :enforcement, :codec_contract]),
         true <- local?(profile.pid),
         true <-
           profile.artifact == value.plan.admission.descriptor.value["artifact"] and
             profile.enforcement == value.plan.admission.registration.value["enforcement"] and
             profile.codec_contract == RegisterCodec.contract(),
         true <- guarantees?(profile.enforcement) do
      limits =
        Map.new(@ceilings, fn {key, cap} ->
          {key, min(cap, value.plan.admission.value["limits"][key])}
        end)

      {:ok, %__MODULE__{value: value, driver_pid: profile.pid, limits: limits}}
    else
      {:error, %Error{}} = error -> error
      _ -> failure(:invalid_configuration)
    end
  end

  defp process_binding(plan) do
    cond do
      plan.admission.descriptor.value["binding"] != %{"id" => "process-codec", "version" => "1.0.0"} or
          is_nil(plan.admission.descriptor.value["artifact"]) ->
        failure(:incompatible_binding)

      plan.admission.registration.value["codec_contract"] != RegisterCodec.contract() or
          plan.admission.descriptor.value["configuration_schema"] !=
            RegisterCodec.configuration_schema() ->
        failure(:schema_mismatch)

      true ->
        :ok
    end
  end

  @doc false
  @spec admit(t()) :: :ok | {:error, Error.t()}
  def admit(config) do
    with {:ok, inputs} <- invoke(fn -> {:ok, config.value.current_inputs.()} end),
         :ok <- Admission.revalidate(config.value.plan.admission, inputs),
         true <- guarantees?(inputs.policy.value["enforcement"]) do
      :ok
    else
      {:error, %Error{}} = error -> error
      _ -> failure(:enforcement_unavailable)
    end
  end

  @doc false
  @spec budget(t(), Context.t(), String.t(), term()) ::
          {:ok, term(), pos_integer()} | {:error, Error.t()}
  def budget(config, context, kind, previous \\ nil) do
    with {:ok, now} <- clock(config),
         :ok <- forward(previous, now) do
      case Context.remaining_ms(context.deadline, now) do
        :infinity ->
          {:ok, now, config.limits[kind]}

        remaining when is_integer(remaining) and remaining > 0 ->
          {:ok, now, min(remaining, config.limits[kind])}

        0 ->
          failure(:deadline_exceeded)

        _ ->
          failure(:enforcement_unavailable)
      end
    end
  end

  @doc false
  @spec timely(t(), Context.t() | nil, term(), pos_integer()) :: {:ok, term()} | {:error, Error.t()}
  def timely(config, context, start, budget) do
    with {:ok, now} <- clock(config),
         {:ok, elapsed} <- elapsed(start, now),
         true <- elapsed >= 0 and elapsed < budget,
         true <- remaining?(context, now) do
      {:ok, now}
    else
      {:error, %Error{}} = error -> error
      _ -> failure(:deadline_exceeded)
    end
  end

  @doc false
  @spec clock(t()) :: {:ok, term()} | {:error, Error.t()}
  def clock(config) do
    with {:ok, now} <- invoke(fn -> {:ok, config.value.now.()} end),
         true <- clock?(now) do
      {:ok, now}
    else
      _ -> failure(:enforcement_unavailable)
    end
  end

  defp remaining?(nil, _), do: true

  defp remaining?(context, now) do
    case Context.remaining_ms(context.deadline, now) do
      :infinity -> true
      remaining when is_integer(remaining) and remaining > 0 -> true
      _ -> false
    end
  end

  defp clock?(value) when is_integer(value), do: true

  defp clock?(%DateTime{} = value) do
    try do
      DateTime.to_unix(value, :millisecond)
      true
    rescue
      _ -> false
    end
  end

  defp clock?(_), do: false
  defp forward(nil, _), do: :ok

  defp forward(start, now) do
    with {:ok, elapsed} <- elapsed(start, now), true <- elapsed >= 0 do
      :ok
    else
      _ -> failure(:enforcement_unavailable)
    end
  end

  defp elapsed(start, now) when is_integer(start) and is_integer(now), do: {:ok, now - start}

  defp elapsed(%DateTime{} = start, %DateTime{} = now),
    do: {:ok, DateTime.diff(now, start, :millisecond)}

  defp elapsed(_, _), do: failure(:enforcement_unavailable)
  defp guarantees?(enforcement), do: Enum.all?(@guarantees, &(&1 in enforcement["guarantees"]))
  defp local?(pid), do: is_pid(pid) and node(pid) == node()

  defp closed?(value, keys),
    do:
      is_map(value) and not is_struct(value) and map_size(value) == length(keys) and
        Enum.all?(keys, &Map.has_key?(value, &1))

  @doc false
  @spec driver(t(), atom(), list()) :: :ok | {:error, Error.t()}
  def driver(config, callback, args) do
    {module, driver_config} = config.value.driver

    case invoke(fn ->
           apply(module, callback, Enum.reverse([driver_config | Enum.reverse(args)]))
         end) do
      :ok -> :ok
      {:error, %Error{}} = error -> error
      _ -> failure(:codec_unavailable)
    end
  end

  @doc false
  @spec invoke((-> term())) :: term()
  def invoke(callback) do
    try do
      case callback.() do
        {:error, code} when code in @failures -> failure(code)
        {:error, _} -> failure(:codec_unavailable)
        result -> result
      end
    rescue
      _ -> failure(:codec_unavailable)
    catch
      _, _ -> failure(:codec_unavailable)
    end
  end

  defp failure(code), do: {:error, Error.new(code, :admission, %{})}
end
