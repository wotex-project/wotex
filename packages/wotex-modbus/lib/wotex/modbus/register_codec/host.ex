defmodule Wotex.Modbus.RegisterCodec.Host do
  @moduledoc """
  Explicit, supervised register process-codec owner with one active request.

  Supply a process-codec Plan, startup Context, local consumer `owner`, trusted
  `{driver_module, driver_config}`, and zero-arity `current_inputs` and `now`
  callbacks. Start the driver's independently owned actor first. Callbacks must
  return promptly. There is no default launcher or automatic replacement.

  `start_link/1` begins asynchronous opening; `await_ready/1` waits for the exact
  handshake. Pass `{__MODULE__, pid}` to `Wotex.Runtime.Codec.decode/5`. Each
  exchange revalidates admission and its original deadline. Stop, protocol
  failure, caller loss and owner loss retire the generation with bounded cleanup.
  A cleanup error means custody was not confirmed. Scripted driver evidence
  establishes this owner contract, not native operating-system enforcement.
  """
  @behaviour Wotex.Runtime.Codec.Executor
  use GenServer

  alias Wotex.Modbus.RegisterCodec.Host.Configuration
  alias Wotex.Runtime.Codec.{Call, Result, Wire}
  alias Wotex.Runtime.Implementation.Error

  @safe 9_007_199_254_740_991
  @failures ~w(artifact_unverified enforcement_unavailable startup_failed codec_unavailable overloaded cleanup_unconfirmed)a

  @doc "Returns a temporary child specification with an inspection-safe start argument."
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(value) do
    config =
      case Configuration.new(value) do
        {:ok, config} -> config
        _ -> %Configuration{value: value}
      end

    %{id: __MODULE__, start: {__MODULE__, :start_link, [config]}, restart: :temporary}
  end

  @doc "Validates explicit configuration and begins opening without waiting for ready."
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(value) do
    with {:ok, config} <- Configuration.new(value) do
      GenServer.start_link(__MODULE__, config)
    end
  end

  @doc "Admits one startup waiter and returns only after ready or bounded terminal cleanup."
  @spec await_ready(term()) :: :ok | {:error, Error.t()}
  def await_ready(pid), do: request(pid, :await_ready)

  @doc "Drains the generation and waits for the driver's bounded cleanup result."
  @spec stop(term()) :: :ok | {:error, Error.t()}
  def stop(pid), do: request(pid, :stop)

  @doc "Executes one admitted exchange on an already-started owner; configuration is its pid."
  @impl Wotex.Runtime.Codec.Executor
  @spec decode(term(), term(), term(), term()) :: {:ok, Result.t()} | {:error, Error.t()}
  def decode(input, metadata, call, pid), do: request(pid, {:decode, input, metadata, call})

  defp request(pid, message) when is_pid(pid) and node(pid) == node() do
    try do
      GenServer.call(pid, message, :infinity)
    catch
      :exit, _ -> failure(:codec_unavailable)
    end
  end

  defp request(_, _), do: failure(:invalid_configuration)

  @impl GenServer
  def init(config) do
    {:ok, wire} =
      Wire.new(%{
        frame_bytes: config.limits["frame_bytes"],
        queue_bytes: config.limits["queue_bytes"]
      })

    state = %{
      config: config,
      phase: :opening,
      channel: make_ref(),
      wire: wire,
      owner_ref: Process.monitor(config.value.owner),
      driver_ref: Process.monitor(config.driver_pid),
      ready_waiter: nil,
      stop_waiter: nil,
      pending: nil,
      seq: 1,
      stderr: 0,
      timer: nil,
      start: nil,
      budget: nil,
      last_clock: nil,
      failure: nil,
      opened: false,
      claimed: false
    }

    {:ok, state, {:continue, :open}}
  end

  @impl GenServer
  def handle_continue(:open, state) do
    config = state.config

    with true <- Process.alive?(config.value.owner) and Process.alive?(config.driver_pid),
         :ok <- Configuration.admit(config),
         {:ok, start, budget} <- Configuration.budget(config, config.value.context, "startup_ms") do
      state = %{state | start: start, budget: budget, last_clock: start, claimed: true}

      case Configuration.driver(config, :open, [
             self(),
             config.value.owner,
             state.channel,
             config.value.plan,
             config.limits
           ]) do
        :ok -> {:noreply, arm(state, budget)}
        error -> close(state, error)
      end
    else
      {:error, %Error{}} = error -> close(state, error)
      _ -> close(state, failure(:owner_lost))
    end
  end

  @impl GenServer
  def handle_call(:await_ready, _, %{phase: phase} = state) when phase in [:ready, :pending],
    do: {:reply, :ok, state}

  def handle_call(:await_ready, from, %{phase: phase, ready_waiter: nil} = state)
      when phase in [:opening, :starting], do: {:noreply, %{state | ready_waiter: from}}

  def handle_call(:await_ready, _, %{phase: :closing} = state),
    do: {:reply, failure(:instance_draining), state}

  def handle_call(:await_ready, _, state), do: {:reply, failure(:overloaded), state}

  def handle_call(:stop, from, %{stop_waiter: nil} = state),
    do: close(%{state | stop_waiter: from}, failure(:instance_draining))

  def handle_call(:stop, _, state), do: {:reply, failure(:overloaded), state}

  def handle_call({:decode, _, _, _}, _, %{phase: :pending} = state),
    do: {:reply, failure(:overloaded), state}

  def handle_call({:decode, _, _, _}, _, %{phase: :closing} = state),
    do: {:reply, failure(:instance_draining), state}

  def handle_call({:decode, input, metadata, call}, from, %{phase: :ready} = state),
    do: dispatch(input, metadata, call, from, state)

  def handle_call({:decode, _, _, _}, _, state),
    do: {:reply, failure(:instance_not_ready), state}

  def handle_call(_, _, state), do: {:reply, failure(:invalid_input), state}

  defp dispatch(input, metadata, call, from, state) do
    with :ok <- same_call(call, state.config.value.plan),
         true <- is_binary(input) and byte_size(input) <= 65_536,
         true <- state.seq <= @safe,
         :ok <- Configuration.admit(state.config),
         {:ok, start, budget} <-
           Configuration.budget(state.config, call.context, "request_ms", state.last_clock),
         frame = %{
           "v" => 1,
           "type" => "decode",
           "seq" => state.seq,
           "request_id" => call.context.request_id,
           "budget_ms" => budget,
           "bytes" => %{"type" => "bytes", "base64" => Base.encode64(input)},
           "metadata" => metadata
         },
         {:ok, bytes} <- Wire.encode(frame),
         true <- byte_size(bytes) <= state.config.limits["frame_bytes"] do
      pending = %{from: from, call: call, seq: state.seq, monitor: Process.monitor(elem(from, 0))}

      state = %{
        state
        | pending: pending,
          phase: :pending,
          seq: state.seq + 1,
          start: start,
          budget: budget,
          last_clock: start
      }

      case Configuration.driver(state.config, :write, [state.channel, bytes]) do
        :ok -> {:noreply, arm(state, budget)}
        error -> close(state, error)
      end
    else
      {:error, %Error{code: code}} = error
      when code in [:invalid_configuration, :stale_generation, :correlation_failed] ->
        {:reply, error, state}

      {:error, %Error{}} = error ->
        close(%{state | pending: pending_waiter(from)}, error)

      false when state.seq > @safe ->
        close(%{state | pending: pending_waiter(from)}, failure(:codec_unavailable))

      _ ->
        {:reply, failure(:invalid_input), state}
    end
  end

  defp pending_waiter(from), do: %{from: from, monitor: Process.monitor(elem(from, 0))}

  defp same_call(%Call{} = call, plan) do
    with true <- map_size(call) == 3,
         {:ok, ^call} <- Call.new(call.plan, call.context) do
      cond do
        call.plan.instance_key.instance_id == plan.instance_key.instance_id and
          call.plan.instance_key.consumer_scope == plan.instance_key.consumer_scope and
            call.plan.instance_key.generation != plan.instance_key.generation ->
          failure(:stale_generation)

        call.plan != plan ->
          failure(:correlation_failed)

        true ->
          :ok
      end
    else
      _ -> failure(:invalid_configuration)
    end
  end

  defp same_call(_, _), do: failure(:invalid_configuration)

  @impl GenServer
  def handle_info({:wotex_modbus_codec, channel, _}, %{channel: expected} = state)
      when channel != expected, do: {:noreply, state}

  def handle_info({:wotex_modbus_codec, _, {:closed, outcome}}, %{phase: :closing} = state),
    do: finish(state, outcome)

  def handle_info({:wotex_modbus_codec, _, _}, %{phase: :closing} = state), do: {:noreply, state}
  def handle_info({:wotex_modbus_codec, _, :opened}, %{phase: :opening} = state), do: opened(state)
  def handle_info({:wotex_modbus_codec, _, {:stdout, bytes}}, state), do: stdout(bytes, state)

  def handle_info({:wotex_modbus_codec, _, {:stderr, bytes}}, state) when is_binary(bytes) do
    total = state.stderr + byte_size(bytes)

    if total <= state.config.limits["stderr_bytes"],
      do: {:noreply, %{state | stderr: total}},
      else: close(state, failure(:protocol_fault))
  end

  def handle_info({:wotex_modbus_codec, _, :exited}, state),
    do:
      close(
        state,
        failure(
          if(state.phase in [:opening, :starting], do: :startup_failed, else: :codec_unavailable)
        )
      )

  def handle_info({:wotex_modbus_codec, _, {:failed, code}}, state) when code in @failures,
    do: close(state, failure(code))

  def handle_info({:wotex_modbus_codec, _, _}, state), do: close(state, failure(:protocol_fault))

  def handle_info({:timeout, token}, %{timer: {_, token}, phase: :closing} = state),
    do: finish(state, :unconfirmed)

  def handle_info({:timeout, token}, %{timer: {_, token}} = state),
    do: close(state, failure(:deadline_exceeded))

  def handle_info({:DOWN, ref, :process, _, _}, %{driver_ref: ref} = state),
    do: finish(state, :unconfirmed)

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = state),
    do: close(state, failure(:owner_lost))

  def handle_info({:DOWN, ref, :process, _, _}, %{pending: %{monitor: ref}} = state),
    do: close(state, failure(:owner_lost))

  def handle_info(_, state), do: {:noreply, state}

  defp opened(state) do
    with :ok <- Configuration.admit(state.config),
         {:ok, now} <-
           Configuration.timely(state.config, state.config.value.context, state.start, state.budget),
         {:ok, bytes} <- Wire.encode(hello(state)),
         true <- byte_size(bytes) <= state.config.limits["frame_bytes"],
         :ok <- Configuration.driver(state.config, :write, [state.channel, bytes]) do
      {:noreply, %{state | phase: :starting, opened: true, last_clock: now}}
    else
      {:error, %Error{}} = error -> close(%{state | opened: true}, error)
      _ -> close(%{state | opened: true}, failure(:protocol_fault))
    end
  end

  defp hello(state) do
    plan = state.config.value.plan
    contract = plan.admission.registration.value["codec_contract"]

    %{
      "v" => 1,
      "type" => "hello",
      "instance_id" => plan.instance_key.instance_id,
      "generation" => plan.instance_key.generation,
      "descriptor_sha256" => plan.admission.descriptor.sha256,
      "contract_id" => contract["id"],
      "contract_sha256" => contract["sha256"],
      "configuration_sha256" => plan.configuration_sha256,
      "configuration" => plan.configuration,
      "decode_ms" => state.config.limits["request_ms"]
    }
  end

  defp stdout(<<>>, state), do: {:noreply, state}

  defp stdout(bytes, %{phase: phase} = state) when phase in [:starting, :pending] do
    case Wire.feed(state.wire, bytes) do
      {:ok, [], wire} -> {:noreply, %{state | wire: wire}}
      {:ok, [frame], %{buffer: <<>>} = wire} -> reply_frame(frame, %{state | wire: wire})
      _ -> close(state, failure(:protocol_fault))
    end
  end

  defp stdout(_, state), do: close(state, failure(:protocol_fault))

  defp reply_frame(frame, %{phase: :starting} = state) do
    expected =
      hello(state)
      |> Map.delete("configuration")
      |> Map.put("type", "ready")

    with true <- frame == expected,
         :ok <- Configuration.admit(state.config),
         {:ok, now} <-
           Configuration.timely(state.config, state.config.value.context, state.start, state.budget) do
      reply(state.ready_waiter, :ok)
      {:noreply, %{cancel(state) | phase: :ready, ready_waiter: nil, last_clock: now}}
    else
      {:error, %Error{}} = error -> close(state, error)
      _ -> close(state, failure(:protocol_fault))
    end
  end

  defp reply_frame(frame, %{phase: :pending} = state) do
    pending = state.pending

    with true <-
           frame["type"] in ["result", "refusal"] and frame["seq"] == pending.seq and
             frame["request_id"] == pending.call.context.request_id,
         result = output(frame, pending.call),
         :ok <- Configuration.admit(state.config),
         {:ok, now} <-
           Configuration.timely(state.config, pending.call.context, state.start, state.budget) do
      reply(pending.from, result)
      Process.demonitor(pending.monitor, [:flush])
      {:noreply, %{cancel(state) | phase: :ready, pending: nil, last_clock: now}}
    else
      {:error, %Error{}} = error -> close(state, error)
      _ -> close(state, failure(:protocol_fault))
    end
  end

  defp output(%{"type" => "result", "value" => value}, call), do: Result.new(value, call)
  defp output(%{"code" => "invalid_input"}, _), do: failure(:invalid_input)
  defp output(%{"code" => "unsupported_format"}, _), do: failure(:unsupported_format)
  defp output(%{"code" => "unsupported_value"}, _), do: failure(:unsupported_value)
  defp output(%{"code" => "output_limit"}, _), do: failure(:output_limit)

  defp close(%{phase: :closing} = state, _), do: {:noreply, state}

  defp close(%{claimed: false} = state, error),
    do: finish(%{state | phase: :closing, failure: error}, :confirmed_local)

  defp close(state, error) do
    state = %{cancel(state) | phase: :closing, failure: error}

    start =
      case Configuration.clock(state.config) do
        {:ok, now} -> now
        _ -> nil
      end

    budget = state.config.limits["shutdown_ms"]
    state = %{state | start: start, budget: budget}

    with :ok <- stop_frame(state),
         :ok <- Configuration.driver(state.config, :close, [state.channel, budget]) do
      {:noreply, arm(state, budget)}
    else
      _ -> finish(state, :unconfirmed)
    end
  end

  defp stop_frame(%{opened: false}), do: :ok

  defp stop_frame(state) do
    {:ok, bytes} = Wire.encode(%{"v" => 1, "type" => "stop"})
    # A failed stop submission does not suppress custody cleanup.
    Configuration.driver(state.config, :write, [state.channel, bytes])
    :ok
  end

  defp finish(state, outcome) do
    confirmed =
      state.phase == :closing and outcome == :confirmed_local and
        (not state.claimed or
           match?({:ok, _}, Configuration.timely(state.config, nil, state.start, state.budget)))

    error = if confirmed, do: state.failure, else: failure(:cleanup_unconfirmed)

    if state.pending do
      Process.demonitor(state.pending.monitor, [:flush])
      reply(state.pending.from, error)
    end

    reply(state.ready_waiter, error)
    reply(state.stop_waiter, if(confirmed, do: :ok, else: error))
    {:stop, :normal, cancel(state)}
  end

  defp reply(nil, _), do: :ok
  defp reply(from, result), do: GenServer.reply(from, result)

  defp arm(state, budget) do
    token = make_ref()
    %{state | timer: {Process.send_after(self(), {:timeout, token}, budget), token}}
  end

  defp cancel(%{timer: nil} = state), do: state

  defp cancel(%{timer: {ref, _}} = state) do
    Process.cancel_timer(ref)
    %{state | timer: nil}
  end

  @impl GenServer
  def format_status(status),
    do: Map.merge(status, %{state: :redacted, message: :redacted, reason: :redacted, log: []})

  defp failure(code), do: {:error, Error.new(code, :execution, %{})}
end
