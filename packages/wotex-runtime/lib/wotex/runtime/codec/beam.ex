defmodule Wotex.Runtime.Codec.Beam do
  @moduledoc """
  Trusted decoder tasks under an explicit consumer-owned Task.Supervisor.

  Supply a separate local supervisor with `max_children: 1` for each instance,
  the installed decoder and exact contract, and current-input/clock callbacks.
  One budget includes supervised startup, decoding and output admission.
  Stalled startup and owner loss retain bounded custody; unresolved cleanup is
  reported explicitly. Loading starts nothing. No VM or descendant isolation
  is claimed for trusted code.
  """
  @behaviour Wotex.Runtime.Codec.Executor
  alias Wotex.Runtime.Codec.Beam.Execution
  alias Wotex.Runtime.Codec.{Call, Grammar, Result}
  alias Wotex.Runtime.Context
  alias Wotex.Runtime.Implementation.{Admission, Error}
  alias Wotex.Runtime.Implementation.Grammar, as: ImplementationGrammar

  @keys [:decoder, :contract, :task_supervisor, :current_inputs, :now]
  @refusals [:invalid_input, :unsupported_format, :unsupported_value, :output_limit]

  @doc "Runs one bounded temporary decoder task after current admission and deadline checks."
  @impl Wotex.Runtime.Codec.Executor
  @spec decode(term(), term(), term(), term()) :: {:ok, Result.t()} | {:error, Error.t()}
  def decode(input, metadata, call, config) do
    try do
      admitted_decode(input, metadata, call, config)
    rescue
      _ -> failure(:codec_unavailable)
    catch
      _, _ -> failure(:codec_unavailable)
    end
  end

  defp admitted_decode(input, metadata, call, config) do
    with :ok <- Call.validate(call),
         :ok <- configuration(config, call),
         true <- is_binary(input) and byte_size(input) <= 65_536,
         true <- Grammar.flat?(metadata),
         :ok <- Admission.revalidate(call.plan.admission, config.current_inputs.()),
         {:ok, start, budget} <- budget(call, config.now.()) do
      work = fn ->
        with :ok <- Admission.revalidate(call.plan.admission, config.current_inputs.()),
             :ok <- timely(call, start, budget, config.now.()) do
          invoke(config.decoder, input, metadata, call.plan.configuration)
        end
      end

      cleanup_ms = min(1000, call.plan.admission.value["limits"]["shutdown_ms"])

      Execution.run(config.task_supervisor, budget, cleanup_ms, work, fn returned ->
        result = output(returned, call)

        with :ok <- Admission.revalidate(call.plan.admission, config.current_inputs.()),
             :ok <- timely(call, start, budget, config.now.()) do
          result
        end
      end)
    else
      {:error, %Error{}} = error -> error
      _ -> failure(:invalid_input)
    end
  end

  defp configuration(config, call) do
    cond do
      not ImplementationGrammar.closed?(config, @keys) ->
        failure(:invalid_configuration)

      call.plan.admission.descriptor.value["binding"]["id"] != "beam-codec" ->
        failure(:incompatible_binding)

      config.contract != call.plan.admission.registration.value["codec_contract"] ->
        failure(:schema_mismatch)

      not is_atom(config.decoder) or not is_pid(config.task_supervisor) or
        node(config.task_supervisor) != node() or
        not is_function(config.current_inputs, 0) or not is_function(config.now, 0) ->
        failure(:invalid_configuration)

      true ->
        :ok
    end
  end

  defp budget(call, now) do
    maximum = min(1000, call.plan.admission.value["limits"]["request_ms"])

    case {clock?(now), Context.remaining_ms(call.context.deadline, now)} do
      {true, :infinity} ->
        {:ok, now, maximum}

      {true, remaining} when is_integer(remaining) and remaining > 0 ->
        {:ok, now, min(maximum, remaining)}

      {true, 0} ->
        failure(:deadline_exceeded)

      _ ->
        failure(:enforcement_unavailable)
    end
  end

  defp timely(call, start, budget, now) do
    with {:ok, elapsed} <- elapsed(start, now),
         {:ok, _, _} <- budget(call, now),
         true <- elapsed >= 0 and elapsed < budget do
      :ok
    else
      {:error, %Error{}} = error -> error
      _ -> failure(:deadline_exceeded)
    end
  end

  defp elapsed(start, now) when is_integer(start) and is_integer(now), do: {:ok, now - start}

  defp elapsed(%DateTime{} = start, %DateTime{} = now),
    do: {:ok, DateTime.diff(now, start, :millisecond)}

  defp elapsed(_, _), do: failure(:enforcement_unavailable)

  defp clock?(%DateTime{} = value) do
    try do
      DateTime.to_unix(value, :millisecond)
      true
    rescue
      _ -> false
    end
  end

  defp clock?(value), do: is_integer(value)

  defp invoke(decoder, input, metadata, configuration) do
    try do
      case decoder.decode(input, metadata, configuration) do
        {:ok, node} -> {:ok, node}
        {:error, code} when code in @refusals -> failure(code)
        _ -> failure(:protocol_fault)
      end
    rescue
      _ -> failure(:codec_unavailable)
    catch
      _, _ -> failure(:codec_unavailable)
    end
  end

  defp failure(code), do: {:error, Error.new(code, :decode, %{})}

  defp output({:ok, node}, call) do
    case Result.new(node, call) do
      {:ok, _} = success -> success
      {:error, %Error{code: :output_limit}} = error -> error
      _ -> failure(:protocol_fault)
    end
  end

  defp output({:error, %Error{}} = error, _), do: error
end
