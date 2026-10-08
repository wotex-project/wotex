defmodule Wotex.Runtime.Codec.Beam do
  @moduledoc """
  Trusted decoder tasks under an explicit consumer-owned Task.Supervisor.

  Supply a separate supervisor with `max_children: 1` for each instance,
  the installed decoder and exact contract, and current-input/clock callbacks.
  Loading starts nothing. This executor claims no VM or descendant isolation.
  """
  @behaviour Wotex.Runtime.Codec.Executor
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
         {:ok, start, budget} <- budget(call, config.now.()),
         {:ok, task} <- start_task(config, input, metadata, call.plan.configuration),
         {:ok, returned} <- await(task, budget),
         result = output(returned, call),
         :ok <- Admission.revalidate(call.plan.admission, config.current_inputs.()),
         :ok <- timely(call, start, budget, config.now.()) do
      result
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

  defp start_task(config, input, metadata, configuration) do
    decoder = config.decoder
    owner = self()
    custodian = spawn(fn -> custody(owner) end)

    try do
      {:ok,
       Task.Supervisor.async_nolink(config.task_supervisor, fn ->
         with :ok <- attach(custodian) do
           invoke(decoder, input, metadata, configuration)
         end
       end)}
    rescue
      RuntimeError ->
        Process.exit(custodian, :kill)
        failure(:overloaded)
    end
  end

  defp custody(owner) do
    Process.flag(:trap_exit, true)
    owner_ref = Process.monitor(owner)

    receive do
      {:attach, worker, tag} ->
        worker_ref = Process.monitor(worker)
        send(worker, {tag, :attached})
        hold(owner_ref, worker_ref, worker)

      {:DOWN, ^owner_ref, :process, _, _} ->
        :ok
    after
      1000 -> :ok
    end
  end

  defp hold(owner_ref, worker_ref, worker) do
    receive do
      {:DOWN, ^owner_ref, :process, _, _} ->
        Process.exit(worker, :kill)
        reap(worker_ref)

      {:DOWN, ^worker_ref, :process, _, _} ->
        :ok

      {:EXIT, _, _} ->
        hold(owner_ref, worker_ref, worker)
    end
  end

  defp attach(custodian) do
    ref = Process.monitor(custodian)
    Process.link(custodian)
    send(custodian, {:attach, self(), ref})

    receive do
      {^ref, :attached} ->
        Process.demonitor(ref, [:flush])
        :ok

      {:DOWN, ^ref, :process, _, _} ->
        failure(:codec_unavailable)
    after
      1000 -> failure(:codec_unavailable)
    end
  end

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

  defp await(task, budget) do
    ref = Process.monitor(task.pid)

    result =
      case Task.yield(task, budget) do
        {:ok, result} ->
          {:ok, result}

        {:exit, _} ->
          failure(:codec_unavailable)

        nil ->
          Task.shutdown(task, :brutal_kill)
          failure(:deadline_exceeded)
      end

    case reap(ref) do
      :ok -> result
      _ -> failure(:cleanup_unconfirmed)
    end
  end

  defp reap(ref) do
    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    after
      1000 ->
        Process.demonitor(ref, [:flush])
        :unconfirmed
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
