defmodule Wotex.Matter.Native.Connection do
  @moduledoc """
  Owns the Port and request correlation state for one native controller.

  `Wotex.Matter.Native` starts this process explicitly and monitors the caller
  that created it. The process validates the fixed startup identity, assigns
  increasing native request IDs, accepts one response for the expected ID, and
  closes the Port when the caller or connection terminates. A missed response
  deadline expires the generation so a delayed frame cannot be correlated with
  later work. It is an implementation module; consumers use
  `Wotex.Matter.Native` and its opaque `Wotex.Matter.Native.Handle`.
  """

  use GenServer

  alias Wotex.Matter.{Error, Subscription}
  alias Wotex.Matter.Native.Wire

  @sdk_revision "250a9e6c50ee2068107f3c4808b680f5f2925415"
  @maximum_line_bytes 131_071
  @cleanup_timeout 1_000
  @response_grace 50

  @spec start(pid(), map()) ::
          {:ok, pid(), String.t()} | {:error, Error.t()}
  def start(owner, options) do
    deadline = System.monotonic_time(:millisecond) + options.timeout

    case GenServer.start(__MODULE__, {owner, options, deadline}) do
      {:ok, pid} ->
        try do
          case GenServer.call(pid, :identity) do
            {:ok, generation} -> {:ok, pid, generation}
            {:error, _} = error -> error
          end
        catch
          :exit, _ -> {:error, Error.new(:controller_start_failed)}
        end

      {:error, %Error{}} = error ->
        error

      {:error, {:shutdown, %Error{} = error}} ->
        {:error, error}

      {:error, _} ->
        {:error, Error.new(:controller_start_failed)}
    end
  end

  @spec request(pid(), String.t(), map(), pos_integer()) ::
          {:ok, term()} | {:error, Error.t()}
  def request(pid, generation, message, timeout),
    do: call(pid, {:request, generation, message, timeout}, timeout)

  @spec subscribe(pid(), String.t(), map(), pid(), pos_integer()) ::
          {:ok, Subscription.t()} | {:error, Error.t()}
  def subscribe(pid, generation, request, receiver, timeout),
    do: call(pid, {:subscribe, generation, request, receiver, timeout}, timeout)

  @spec unsubscribe(pid(), String.t(), Subscription.t(), pos_integer()) ::
          :ok | {:error, Error.t()}
  def unsubscribe(pid, generation, subscription, timeout) do
    if Process.alive?(pid) do
      case call(pid, {:unsubscribe, generation, subscription, timeout}, timeout) do
        {:ok, nil} -> :ok
        {:error, _} = error -> error
      end
    else
      if valid_subscription_handle?(subscription, pid),
        do: :ok,
        else: {:error, Error.new(:invalid_handle)}
    end
  end

  @spec health(pid(), String.t(), pos_integer()) ::
          {:ok, map()} | {:error, Error.t()}
  def health(pid, generation, timeout),
    do: call(pid, {:health, generation, timeout}, timeout)

  @doc false
  @spec invalidate(pid(), String.t()) :: {:ok, nil} | {:error, Error.t()}
  def invalidate(pid, generation), do: call(pid, {:invalidate, generation}, @cleanup_timeout)

  @spec disconnect(pid(), String.t(), pos_integer()) :: :ok | {:error, Error.t()}
  def disconnect(pid, generation, timeout \\ @cleanup_timeout) do
    if Process.alive?(pid) do
      case call(pid, {:disconnect, generation}, timeout) do
        {:ok, nil} -> :ok
        {:error, %Error{code: :transport_closed}} -> :ok
        {:error, _} = error -> error
      end
    else
      :ok
    end
  end

  @impl GenServer
  def init({owner, options, deadline}) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(owner)
    generation = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    case open_port(options.executable) do
      {:ok, port} ->
        case handshake(port, owner_monitor, generation, options, deadline) do
          :ok ->
            {:ok,
             %{
               port: port,
               owner_monitor: owner_monitor,
               generation: generation,
               fabric_id: options.fabric_id,
               next_id: 2,
               subscriptions: %{},
               subscription_ids: %{},
               subscription_monitors: %{},
               closed_references: MapSet.new(),
               next_report_sequence: 1,
               acknowledged_sequence: 0,
               acknowledged_bytes: 0,
               pending_reports: %{},
               internal_requests: %{}
             }}

          {:error, %Error{} = error} ->
            close_port(port)
            {:stop, {:shutdown, error}}
        end

      {:error, %Error{} = error} ->
        {:stop, {:shutdown, error}}
    end
  end

  @impl GenServer
  def handle_call({:bounded, message, deadline}, from, state) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:reply, {:error, Error.new(:timeout)}, state}
    else
      message
      |> remaining_budget(remaining)
      |> handle_call(from, Map.put(state, :call_deadline, deadline))
      |> clear_call_deadline()
    end
  end

  def handle_call(:identity, _, state),
    do: {:reply, {:ok, state.generation}, state}

  def handle_call({:invalidate, generation}, _, state) do
    if generation == state.generation,
      do: {:stop, :normal, {:ok, nil}, state},
      else: {:reply, {:error, Error.new(:invalid_handle)}, state}
  end

  def handle_call({:request, generation, message, timeout}, _, state) do
    cond do
      generation != state.generation ->
        {:reply, {:error, Error.new(:invalid_handle)}, state}

      not Map.has_key?(message, :type) or not is_atom(message.type) or
          not Enum.all?(Map.keys(message), &is_atom/1) ->
        {:reply, {:error, Error.new(:invalid_request)}, state}

      true ->
        parameters =
          message
          |> Map.delete(:type)
          |> stringify_keys()

        operation =
          message
          |> Map.fetch!(:type)
          |> Atom.to_string()

        state
        |> execute(operation, parameters, timeout)
        |> decode_operation_reply(message.type)
    end
  end

  def handle_call({:health, generation, timeout}, _, state) do
    if generation == state.generation do
      execute(state, "health", %{}, timeout)
    else
      {:reply, {:error, Error.new(:invalid_handle)}, state}
    end
  end

  def handle_call({:subscribe, generation, request, receiver, timeout}, _, state) do
    cond do
      generation != state.generation ->
        {:reply, {:error, Error.new(:invalid_handle)}, state}

      map_size(state.subscriptions) >= 64 or MapSet.size(state.closed_references) >= 1_024 ->
        {:reply, {:error, Error.new(:busy)}, state}

      not Process.alive?(receiver) ->
        {:reply, {:error, Error.new(:receiver_closed)}, state}

      true ->
        reference = make_ref()
        native_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
        monitor = Process.monitor(receiver)

        subscription = %{
          reference: reference,
          native_id: native_id,
          generation: 1,
          handle_generation: 1,
          receiver: receiver,
          monitor: monitor,
          queue_limit: request.queue_limit,
          resubscribe: request.resubscribe,
          kind: request.kind,
          paths: request.paths,
          status: :establishing,
          close_result: :cancelled,
          retiring_generation: nil,
          retiring_last_report_sequence: nil,
          recovery_attempt: 0,
          buffered: [],
          last_report_sequence: 0
        }

        parameters =
          request
          |> Map.put(:subscription_id, native_id)
          |> stringify_keys()

        prepared = put_subscription(state, subscription)

        case request_frame(prepared, "subscribe", parameters, timeout) do
          {:ok, result, next_state} ->
            case establish_subscription(result, subscription, next_state) do
              {:ok, handle, established} ->
                send(self(), {:flush_subscription, reference})
                {:reply, {:ok, handle}, established}

              {:error, error, failed} ->
                {:reply, {:error, error}, drop_subscription(failed, reference)}
            end

          {:error, error, next_state} ->
            error_reply(error, drop_subscription(next_state, reference))
        end
    end
  end

  def handle_call({:unsubscribe, generation, subscription, timeout}, _, state) do
    with true <- generation == state.generation,
         :ok <- validate_owned_subscription(subscription, state) do
      if MapSet.member?(state.closed_references, subscription.reference) do
        {:reply, {:ok, nil}, state}
      else
        current = Map.fetch!(state.subscriptions, subscription.reference)

        closing =
          state
          |> put_in([:subscriptions, subscription.reference, :status], :closing)
          |> put_in([:subscriptions, subscription.reference, :close_result], :cancelled)

        parameters = %{
          "subscription_id" => current.native_id,
          "generation" => current.generation
        }

        case request_frame(closing, "unsubscribe", parameters, timeout) do
          {:ok, nil, next_state} ->
            if Map.has_key?(next_state.subscriptions, subscription.reference) do
              {:stop, :normal, {:error, Error.new(:invalid_frame)}, next_state}
            else
              {:reply, {:ok, nil}, next_state}
            end

          {:ok, _, next_state} ->
            {:stop, :normal, {:error, Error.new(:invalid_frame)}, next_state}

          {:error, error, next_state} ->
            error_reply(error, next_state)
        end
      end
    else
      _ -> {:reply, {:error, Error.new(:invalid_handle)}, state}
    end
  end

  def handle_call({:disconnect, generation}, _, state) do
    if generation == state.generation do
      case request_frame(state, "close", %{}, @cleanup_timeout) do
        {:ok, nil, next_state} ->
          case await_close_exit(next_state) do
            :ok -> {:stop, :normal, {:ok, nil}, %{next_state | port: nil}}
            {:error, error} -> {:stop, :normal, {:error, error}, next_state}
          end

        {:ok, _, next_state} ->
          {:stop, :normal, {:error, Error.new(:invalid_frame)}, next_state}

        {:error, error, next_state} ->
          {:stop, :normal, {:error, error}, next_state}
      end
    else
      {:reply, {:error, Error.new(:invalid_handle)}, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _, _}, %{owner_monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    case Map.fetch(state.subscription_monitors, monitor) do
      {:ok, reference} ->
        {:noreply, cancel_subscription(state, reference, :receiver_closed)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:flush_subscription, reference}, state),
    do: {:noreply, flush_subscription(state, reference)}

  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state)
      when byte_size(line) <= @maximum_line_bytes do
    case decode_async_line(line, state) do
      {:ok, next_state} -> {:noreply, next_state}
      {:error, _} -> {:stop, :normal, state}
    end
  end

  def handle_info({port, {:data, {:noeol, _}}}, %{port: port} = state),
    do: {:stop, :normal, state}

  def handle_info({port, {:exit_status, _}}, %{port: port} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: {:stop, :normal, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) when is_map(state) do
    Enum.each(Map.get(state, :subscriptions, %{}), fn {_reference, subscription} ->
      result =
        if subscription.status == :closing,
          do: subscription.close_result,
          else: :session_closed

      emit_subscription(:close, subscription.kind, result)
    end)

    close_port(Map.get(state, :port))
    :ok
  end

  def terminate(_, _), do: :ok

  defp execute(state, operation, parameters, timeout) do
    case request_frame(state, operation, parameters, timeout) do
      {:ok, result, next_state} ->
        {:reply, {:ok, result}, next_state}

      {:error, error, next_state} ->
        error_reply(error, next_state)
    end
  end

  defp error_reply(error, state) do
    if error.code == :timeout or Map.get(state, :channel_failed, false),
      do: {:stop, :normal, {:error, error}, state},
      else: {:reply, {:error, error}, state}
  end

  defp decode_operation_reply({:reply, {:ok, result}, state}, type) do
    case Wire.decode(type, result) do
      {:ok, decoded} ->
        if System.monotonic_time(:millisecond) <= state.call_deadline do
          {:reply, {:ok, decoded}, state}
        else
          effect = if type in [:write, :invoke], do: :unknown, else: :none
          {:stop, :normal, {:error, Error.new(:timeout) |> Error.with_effect(effect)}, state}
        end

      {:error, error} ->
        effect = if type in [:write, :invoke], do: :unknown, else: :none
        {:stop, :normal, {:error, Error.with_effect(error, effect)}, state}
    end
  end

  defp decode_operation_reply(reply, _), do: reply

  defp remaining_budget({:request, generation, message, timeout}, remaining),
    do: {:request, generation, message, min(timeout, remaining)}

  defp remaining_budget({:health, generation, timeout}, remaining),
    do: {:health, generation, min(timeout, remaining)}

  defp remaining_budget({:subscribe, generation, request, receiver, timeout}, remaining),
    do: {:subscribe, generation, request, receiver, min(timeout, remaining)}

  defp remaining_budget({:unsubscribe, generation, subscription, timeout}, remaining),
    do: {:unsubscribe, generation, subscription, min(timeout, remaining)}

  defp remaining_budget(message, _), do: message

  defp clear_call_deadline({:reply, reply, state}),
    do: {:reply, reply, Map.delete(state, :call_deadline)}

  defp clear_call_deadline({:stop, reason, reply, state}),
    do: {:stop, reason, reply, Map.delete(state, :call_deadline)}

  defp request_frame(state, operation, parameters, timeout) do
    id = Integer.to_string(state.next_id)

    frame = %{
      "version" => 1,
      "id" => id,
      "operation" => operation,
      "parameters" => parameters,
      "timeout_ms" => timeout
    }

    next_state = %{state | next_id: state.next_id + 1}

    deadline = Map.get(state, :call_deadline, System.monotonic_time(:millisecond) + timeout)

    case send_request_frame(state.port, frame, deadline) do
      :ok ->
        case await_response_until(next_state, id, deadline) do
          {:ok, result, response_state} ->
            {:ok, result, response_state}

          {:error, error, response_state} ->
            {:error, error, response_state}

          {:channel_error, error, response_state} ->
            effect = if operation in ["write", "invoke"], do: :unknown, else: :none

            {:error, Error.with_effect(error, effect),
             Map.put(response_state, :channel_failed, true)}
        end

      {:error, :transport_closed} ->
        {:error, Error.new(:transport_closed), Map.put(next_state, :channel_failed, true)}

      {:error, code} ->
        {:error, Error.new(code), next_state}
    end
  end

  defp call(pid, message, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    GenServer.call(pid, {:bounded, message, deadline}, timeout + 100)
  catch
    :exit, {:noproc, _} -> {:error, Error.new(:transport_closed)}
    :exit, {:timeout, _} -> {:error, call_error(:timeout, message)}
    :exit, _ -> {:error, call_error(:transport_closed, message)}
  end

  defp call_error(code, {:request, _, %{type: type}, _}) when type in [:write, :invoke],
    do: Error.new(code) |> Error.with_effect(:unknown)

  defp call_error(code, _), do: Error.new(code)

  defp open_port(executable) do
    {:ok, %{type: :regular, mode: mode}} = File.stat("/bin/kill")
    true = Bitwise.band(mode, 0o111) != 0

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [:binary, :exit_status, :use_stdio, {:line, @maximum_line_bytes}]
      )

    {:ok, port}
  rescue
    _ -> {:error, Error.new(:controller_start_failed)}
  end

  defp handshake(port, owner_monitor, generation, options, deadline) do
    with :ok <- await_ready(port, owner_monitor, deadline),
         true <- send_frame(port, flow_frame(generation)),
         :ok <- send_request_frame(port, open_frame(options), deadline),
         {:ok, identity} <- handshake_response(port, owner_monitor, "1", deadline),
         :ok <- controller_identity(identity, options) do
      :ok
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, code} when is_atom(code) -> {:error, Error.new(code)}
      _ -> {:error, Error.new(:controller_start_failed)}
    end
  end

  defp controller_identity(identity, options) do
    expected = %{
      "lifecycle" => "persistent",
      "fabric_id" => options.fabric_id,
      "controller_node_id" => options.controller_node_id,
      "vendor_id" => options.vendor_id
    }

    if identity == expected,
      do: :ok,
      else: {:error, Error.new(:invalid_controller_identity)}
  end

  defp handshake_response(port, owner_monitor, id, deadline) do
    with {:ok, line} <- await_line_until(port, owner_monitor, deadline),
         {:ok, frame} <- Wire.frame(line) do
      case decode_response(frame, id) do
        {:ok, _} = result -> result
        {:error, %Error{}} = error -> error
        _ -> {:error, Error.new(:invalid_frame)}
      end
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp await_ready(port, owner_monitor, deadline) do
    case await_line_until(port, owner_monitor, deadline) do
      {:ok, line} ->
        with {:ok, frame} <- Wire.frame(line),
             true <-
               frame == %{
                 "version" => 1,
                 "event" => "ready",
                 "backend" => "matter-native",
                 "revision" => @sdk_revision
               } do
          :ok
        else
          _ -> {:error, Error.new(:invalid_ready)}
        end

      {:error, _} = error ->
        error
    end
  end

  defp await_response_until(state, id, deadline) do
    remaining = max(deadline + @response_grace - System.monotonic_time(:millisecond), 0)

    with true <- remaining > 0,
         {:ok, line} <-
           await_line_until(state.port, state.owner_monitor, deadline + @response_grace),
         {:ok, frame} <- Wire.frame(line) do
      case decode_response(frame, id) do
        {:ok, result} ->
          if System.monotonic_time(:millisecond) <= deadline,
            do: {:ok, result, state},
            else: {:channel_error, Error.new(:timeout), state}

        {:error, %Error{} = error} ->
          {:error, error, state}

        :not_response ->
          case decode_async_frame(frame, byte_size(line) + 1, state) do
            {:ok, next_state} -> await_response_until(next_state, id, deadline)
            {:error, error} -> {:channel_error, error, state}
          end
      end
    else
      false -> {:channel_error, Error.new(:timeout), state}
      {:error, %Error{} = error} -> {:channel_error, error, state}
      _ -> {:channel_error, Error.new(:invalid_frame), state}
    end
  end

  defp await_line_until(port, owner_monitor, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, Error.new(:timeout)}
    else
      result =
        receive do
          {^port, {:data, {:eol, line}}} when byte_size(line) <= @maximum_line_bytes ->
            {:ok, line}

          {^port, {:data, {:noeol, _}}} ->
            {:error, Error.new(:response_limit)}

          {^port, {:exit_status, _}} ->
            {:error, Error.new(:transport_closed)}

          {:EXIT, ^port, _} ->
            {:error, Error.new(:transport_closed)}

          {:DOWN, ^owner_monitor, :process, _, _} ->
            {:error, Error.new(:owner_closed)}
        after
          remaining -> {:error, Error.new(:timeout)}
        end

      if System.monotonic_time(:millisecond) < deadline,
        do: result,
        else: {:error, Error.new(:timeout)}
    end
  end

  defp decode_response(
         %{"version" => 1, "id" => id, "ok" => true, "result" => result} = frame,
         id
       )
       when map_size(frame) == 4,
       do: {:ok, result}

  defp decode_response(
         %{"version" => 1, "id" => id, "ok" => false, "error" => error} = frame,
         id
       )
       when map_size(frame) == 4 do
    case Wire.error(error) do
      {:ok, error} -> {:error, error}
      :error -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_response(_, _), do: :not_response

  defp decode_async_line(line, state) do
    with {:ok, frame} <- Wire.frame(line) do
      decode_async_frame(frame, byte_size(line) + 1, state)
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "subscription_status",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "status" => "resubscribing",
           "continuity" => "lost",
           "attempt" => attempt
         } = frame,
         _encoded_bytes,
         state
       )
       when map_size(frame) == 8 and is_binary(native_id) and is_integer(generation) and
              generation > 1 and is_integer(attempt) and attempt in 1..5 do
    with true <- session_generation == state.generation,
         {:ok, reference} <- subscription_reference(state, native_id),
         {:ok, next_state} <- begin_recovery(state, reference, generation, attempt) do
      {:ok, next_state}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "subscription_status",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "status" => "resubscribed",
           "continuity" => "unknown",
           "attempt" => attempt,
           "min_interval_s" => minimum,
           "max_interval_s" => maximum,
           "sdk_subscription_id" => sdk_id
         } = frame,
         _encoded_bytes,
         state
       )
       when map_size(frame) == 11 and is_binary(native_id) and is_integer(generation) and
              generation > 1 and is_integer(attempt) and attempt in 1..5 and
              is_integer(minimum) and minimum in 0..65_535 and is_integer(maximum) and
              maximum in 1..65_535 and minimum <= maximum and is_integer(sdk_id) and
              sdk_id in 0..0xFFFFFFFF do
    with true <- session_generation == state.generation,
         {:ok, reference} <- Map.fetch(state.subscription_ids, {native_id, generation}),
         {:ok, next_state} <-
           finish_recovery(state, reference, generation, attempt, minimum, maximum, sdk_id) do
      {:ok, next_state}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "subscription_report",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "report_sequence" => sequence,
           "kind" => kind,
           "value" => value,
           "metadata" => metadata
         } = frame,
         encoded_bytes,
         state
       )
       when map_size(frame) == 9 and is_binary(native_id) and is_integer(generation) and
              generation > 0 and is_integer(sequence) and sequence > 0 and
              kind in ["attribute", "event"] and is_map(metadata) do
    key = {native_id, generation}

    with true <- session_generation == state.generation,
         true <- sequence == state.next_report_sequence,
         {:ok, reference} <- Map.fetch(state.subscription_ids, key),
         {:ok, delivery} <- Wire.subscription(kind, value, metadata),
         true <- delivery_path_matches?(delivery, Map.fetch!(state.subscriptions, reference)),
         registered <- register_report(state, reference, sequence, encoded_bytes),
         {:ok, next_state} <-
           admit_report(registered, reference, delivery, sequence, encoded_bytes) do
      {:ok, next_state}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "stream_retired",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "last_report_sequence" => last_sequence
         } = frame,
         _encoded_bytes,
         state
       )
       when map_size(frame) == 6 and is_binary(native_id) and is_integer(generation) and
              generation > 0 and is_integer(last_sequence) and last_sequence >= 0 do
    key = {native_id, generation}

    with true <- session_generation == state.generation,
         {:ok, reference} <- Map.fetch(state.subscription_ids, key) do
      retire_stream_generation(state, reference, generation, last_sequence)
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{"version" => 1, "id" => id, "ok" => true, "result" => nil} = frame,
         _bytes,
         state
       )
       when map_size(frame) == 4 and is_binary(id) do
    case Map.pop(state.internal_requests, id) do
      {nil, _} -> {:error, Error.new(:invalid_frame)}
      {_reference, requests} -> {:ok, %{state | internal_requests: requests}}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "subscription_error",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "error" => raw_error
         } = frame,
         _encoded_bytes,
         state
       )
       when map_size(frame) == 6 and is_binary(native_id) and is_integer(generation) and
              generation > 0 do
    key = {native_id, generation}

    with true <- session_generation == state.generation,
         {:ok, reference} <- Map.fetch(state.subscription_ids, key),
         {:ok, error} <- Wire.error(raw_error),
         %{status: status} = subscription <- Map.fetch!(state.subscriptions, reference),
         true <- status in [:active, :establishing, :recovering] do
      send(subscription.receiver, {:wotex_matter, reference, {:error, error}})

      closing =
        state
        |> put_in([:subscriptions, reference, :status], :closing)
        |> put_in([:subscriptions, reference, :close_result], error.code)

      {:ok, closing}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(_, _, _), do: {:error, Error.new(:invalid_frame)}

  defp send_frame(port, frame) do
    case Jason.encode(frame) do
      {:ok, encoded} when byte_size(encoded) + 1 <= @maximum_line_bytes + 1 ->
        Port.command(port, [encoded, ?\n])

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp send_request_frame(port, frame, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))
    frame = Map.put(frame, "timeout_ms", min(frame["timeout_ms"], remaining))

    case Jason.encode(frame) do
      {:ok, encoded} when byte_size(encoded) + 1 <= @maximum_line_bytes + 1 ->
        cond do
          System.monotonic_time(:millisecond) >= deadline -> {:error, :timeout}
          Port.command(port, [encoded, ?\n]) -> :ok
          true -> {:error, :transport_closed}
        end

      _ ->
        {:error, :invalid_request}
    end
  rescue
    _ -> {:error, :transport_closed}
  end

  defp flow_frame(generation),
    do: %{"version" => 1, "event" => "flow_open", "session_generation" => generation}

  defp open_frame(options) do
    %{
      "version" => 1,
      "id" => "1",
      "operation" => "open",
      "parameters" => %{
        "lifecycle" => options.lifecycle,
        "storage_path" => options.storage_path,
        "storage_mode" => options.storage_mode,
        "authority" => options.authority,
        "vendor_id" => options.vendor_id,
        "fabric_id" => options.fabric_id,
        "controller_node_id" => options.controller_node_id,
        "paa_trust_store" => options.paa_trust_store
      },
      "timeout_ms" => options.timeout
    }
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      key = if is_atom(key), do: Atom.to_string(key), else: key
      {key, stringify_keys(value)}
    end)
  end

  defp stringify_keys(values) when is_list(values), do: Enum.map(values, &stringify_keys/1)
  defp stringify_keys({:context, id}) when is_integer(id), do: ["context", id]
  defp stringify_keys(value), do: value

  defp establish_subscription(
         %{
           "subscription_id" => native_id,
           "generation" => generation,
           "min_interval_s" => minimum,
           "max_interval_s" => maximum,
           "sdk_subscription_id" => sdk_id
         } = result,
         subscription,
         state
       )
       when map_size(result) == 5 and native_id == subscription.native_id and
              generation == subscription.generation and is_integer(minimum) and
              minimum in 0..65_535 and is_integer(maximum) and maximum in 1..65_535 and
              minimum <= maximum and is_integer(sdk_id) and sdk_id in 0..0xFFFFFFFF do
    active =
      state
      |> put_in([:subscriptions, subscription.reference, :status], :active)
      |> put_in([:subscriptions, subscription.reference, :min_interval_s], minimum)
      |> put_in([:subscriptions, subscription.reference, :max_interval_s], maximum)
      |> put_in([:subscriptions, subscription.reference, :sdk_subscription_id], sdk_id)

    emit_subscription(:open, subscription.kind, :ok)

    handle = %Subscription{
      pid: self(),
      reference: subscription.reference,
      generation: subscription.handle_generation
    }

    {:ok, handle, active}
  end

  defp establish_subscription(_, subscription, state),
    do: {:error, Error.new(:invalid_frame), drop_subscription(state, subscription.reference)}

  defp put_subscription(state, subscription) do
    key = {subscription.native_id, subscription.generation}

    %{
      state
      | subscriptions: Map.put(state.subscriptions, subscription.reference, subscription),
        subscription_ids: Map.put(state.subscription_ids, key, subscription.reference),
        subscription_monitors:
          Map.put(state.subscription_monitors, subscription.monitor, subscription.reference)
    }
  end

  defp subscription_reference(state, native_id) do
    references =
      for {reference, %{native_id: ^native_id}} <- state.subscriptions,
          do: reference

    case references do
      [reference] -> {:ok, reference}
      _ -> :error
    end
  end

  defp begin_recovery(state, reference, generation, attempt) do
    subscription = Map.fetch!(state.subscriptions, reference)

    cond do
      subscription.resubscribe and subscription.status == :active and
        generation == subscription.generation + 1 and
        attempt == 1 and is_nil(subscription.retiring_generation) ->
        recovering = %{
          subscription
          | status: :recovering,
            retiring_generation: subscription.generation,
            retiring_last_report_sequence: subscription.last_report_sequence,
            generation: generation,
            recovery_attempt: attempt,
            last_report_sequence: 0
        }

        transitioned =
          state
          |> put_in([:subscriptions, reference], recovering)
          |> put_in([:subscription_ids, {subscription.native_id, generation}], reference)

        deliver_subscription_status(transitioned, reference, :resubscribing, %{
          continuity: :lost,
          generation: generation,
          attempt: attempt
        })

      subscription.status == :recovering and generation == subscription.generation and
          attempt == subscription.recovery_attempt + 1 ->
        recovering = put_in(state.subscriptions[reference].recovery_attempt, attempt)

        deliver_subscription_status(recovering, reference, :resubscribing, %{
          continuity: :lost,
          generation: generation,
          attempt: attempt
        })

      true ->
        :error
    end
  end

  defp finish_recovery(state, reference, generation, attempt, minimum, maximum, sdk_id) do
    subscription = Map.fetch!(state.subscriptions, reference)

    if subscription.status == :recovering and generation == subscription.generation and
         attempt == subscription.recovery_attempt and is_nil(subscription.retiring_generation) do
      case deliver_subscription_status(state, reference, :resubscribed, %{
             continuity: :unknown,
             generation: generation,
             attempt: attempt,
             min_interval_s: minimum,
             max_interval_s: maximum,
             sdk_subscription_id: sdk_id
           }) do
        {:ok, delivered} ->
          active =
            delivered
            |> put_in([:subscriptions, reference, :status], :active)
            |> put_in([:subscriptions, reference, :min_interval_s], minimum)
            |> put_in([:subscriptions, reference, :max_interval_s], maximum)
            |> put_in([:subscriptions, reference, :sdk_subscription_id], sdk_id)

          {:ok, active}

        {:overflow, closing} ->
          {:ok, closing}
      end
    else
      :error
    end
  end

  defp deliver_subscription_status(state, reference, status, metadata) do
    subscription = Map.fetch!(state.subscriptions, reference)

    case Process.info(subscription.receiver, :message_queue_len) do
      {:message_queue_len, length} when length < subscription.queue_limit ->
        send(subscription.receiver, {:wotex_matter, reference, {:status, status, metadata}})
        emit_subscription(:deliver, subscription.kind, status)
        {:ok, state}

      _ ->
        error = Error.new(:receiver_overflow)
        send(subscription.receiver, {:wotex_matter, reference, {:error, error}})
        {:overflow, cancel_subscription(state, reference, :receiver_overflow)}
    end
  end

  defp retire_stream_generation(state, reference, generation, last_sequence) do
    subscription = Map.fetch!(state.subscriptions, reference)

    cond do
      subscription.retiring_generation == generation and
        subscription.retiring_last_report_sequence == last_sequence and
          subscription.status in [:recovering, :closing] ->
        transitioned =
          state
          |> consume_retired_reports(reference)
          |> update_in([:subscription_ids], &Map.delete(&1, {subscription.native_id, generation}))
          |> put_in([:subscriptions, reference, :retiring_generation], nil)
          |> put_in([:subscriptions, reference, :retiring_last_report_sequence], nil)

        {:ok, transitioned}

      subscription.status == :closing and subscription.generation == generation and
        subscription.last_report_sequence == last_sequence and
          is_nil(subscription.retiring_generation) ->
        retired =
          state
          |> consume_retired_reports(reference)
          |> retire_subscription(reference)

        {:ok, retired}

      true ->
        {:error, Error.new(:invalid_frame)}
    end
  end

  defp drop_subscription(state, reference) do
    case Map.pop(state.subscriptions, reference) do
      {nil, _} ->
        state

      {subscription, subscriptions} ->
        Process.demonitor(subscription.monitor, [:flush])

        subscription_ids =
          state.subscription_ids
          |> Enum.reject(fn {_key, owner} -> owner == reference end)
          |> Map.new()

        %{
          state
          | subscriptions: subscriptions,
            subscription_ids: subscription_ids,
            subscription_monitors: Map.delete(state.subscription_monitors, subscription.monitor)
        }
    end
  end

  defp retire_subscription(state, reference) do
    subscription = Map.get(state.subscriptions, reference)
    closed = MapSet.put(state.closed_references, reference)

    if subscription do
      emit_subscription(:close, subscription.kind, subscription.close_result)
    end

    state
    |> drop_subscription(reference)
    |> Map.put(:closed_references, closed)
  end

  defp validate_owned_subscription(%Subscription{} = subscription, state) do
    cond do
      not valid_subscription_handle?(subscription, self()) ->
        :error

      MapSet.member?(state.closed_references, subscription.reference) ->
        :ok

      true ->
        case Map.fetch(state.subscriptions, subscription.reference) do
          {:ok, current} when current.handle_generation == subscription.generation -> :ok
          _ -> :error
        end
    end
  end

  defp valid_subscription_handle?(%Subscription{} = subscription, pid),
    do:
      subscription.pid == pid and is_reference(subscription.reference) and
        is_integer(subscription.generation) and subscription.generation > 0

  defp valid_subscription_handle?(_, _), do: false

  defp admit_report(state, reference, delivery, sequence, encoded_bytes) do
    subscription = Map.fetch!(state.subscriptions, reference)

    cond do
      subscription.status == :establishing ->
        if length(subscription.buffered) < subscription.queue_limit do
          buffered = subscription.buffered ++ [{delivery, sequence, encoded_bytes}]
          {:ok, put_in(state.subscriptions[reference].buffered, buffered)}
        else
          {:ok, overflow_subscription(state, reference, sequence, encoded_bytes)}
        end

      subscription.status == :active ->
        {:ok, deliver_report(state, reference, delivery, sequence, encoded_bytes)}

      subscription.status == :closing ->
        {:ok, acknowledge_report(state, sequence, encoded_bytes)}

      true ->
        {:error, Error.new(:invalid_frame)}
    end
  end

  defp flush_subscription(state, reference) do
    case Map.fetch(state.subscriptions, reference) do
      {:ok, %{status: :active, buffered: buffered}} ->
        state = put_in(state.subscriptions[reference].buffered, [])

        Enum.reduce(buffered, state, fn {delivery, sequence, bytes}, acc ->
          if Map.has_key?(acc.subscriptions, reference),
            do: deliver_report(acc, reference, delivery, sequence, bytes),
            else: acknowledge_report(acc, sequence, bytes)
        end)

      _ ->
        state
    end
  end

  defp deliver_report(state, reference, delivery, sequence, encoded_bytes) do
    subscription = Map.fetch!(state.subscriptions, reference)

    case Process.info(subscription.receiver, :message_queue_len) do
      {:message_queue_len, length} when length < subscription.queue_limit ->
        send(subscription.receiver, {:wotex_matter, reference, delivery})
        emit_subscription(:deliver, subscription.kind, :ok)
        acknowledge_report(state, sequence, encoded_bytes)

      _ ->
        overflow_subscription(state, reference, sequence, encoded_bytes)
    end
  end

  defp overflow_subscription(state, reference, sequence, encoded_bytes) do
    subscription = Map.fetch!(state.subscriptions, reference)
    error = Error.new(:receiver_overflow)
    send(subscription.receiver, {:wotex_matter, reference, {:error, error}})

    state
    |> acknowledge_report(sequence, encoded_bytes)
    |> cancel_subscription(reference, :receiver_overflow)
  end

  defp acknowledge_report(state, sequence, encoded_bytes) do
    case Map.fetch(state.pending_reports, sequence) do
      {:ok, %{bytes: ^encoded_bytes}} ->
        state
        |> put_in([:pending_reports, sequence, :consumed], true)
        |> advance_acknowledgement()

      _ ->
        state
    end
  end

  defp register_report(state, reference, sequence, encoded_bytes) do
    pending = %{
      reference: reference,
      bytes: encoded_bytes,
      consumed: false
    }

    state
    |> Map.put(:next_report_sequence, sequence + 1)
    |> put_in([:subscriptions, reference, :last_report_sequence], sequence)
    |> Map.put(:pending_reports, Map.put(state.pending_reports, sequence, pending))
  end

  defp consume_retired_reports(state, reference) do
    pending =
      Map.new(state.pending_reports, fn {sequence, report} ->
        if report.reference == reference,
          do: {sequence, %{report | consumed: true}},
          else: {sequence, report}
      end)

    state
    |> Map.put(:pending_reports, pending)
    |> advance_acknowledgement()
  end

  defp advance_acknowledgement(state) do
    {sequence, bytes, pending} =
      consume_prefix(
        state.acknowledged_sequence + 1,
        state.acknowledged_bytes,
        state.pending_reports
      )

    if sequence == state.acknowledged_sequence do
      state
    else
      frame = %{
        "version" => 1,
        "event" => "report_ack",
        "session_generation" => state.generation,
        "report_sequence" => sequence,
        "acknowledged_bytes" => bytes
      }

      if send_frame(state.port, frame) do
        %{
          state
          | acknowledged_sequence: sequence,
            acknowledged_bytes: bytes,
            pending_reports: pending
        }
      else
        state
      end
    end
  end

  defp consume_prefix(sequence, bytes, pending) do
    case Map.fetch(pending, sequence) do
      {:ok, %{bytes: report_bytes, consumed: true}} ->
        consume_prefix(sequence + 1, bytes + report_bytes, Map.delete(pending, sequence))

      _ ->
        {sequence - 1, bytes, pending}
    end
  end

  defp delivery_path_matches?({:ok, _, %{kind: kind, path: path}}, subscription) do
    kind == subscription.kind and
      Enum.any?(subscription.paths, fn expected ->
        expected.fabric_id == path.fabric_id and expected.node_id == path.node_id and
          expected.endpoint == path.endpoint and expected.cluster == path.cluster and
          expected.member == path.member
      end)
  end

  defp cancel_subscription(state, reference, result) do
    case Map.fetch(state.subscriptions, reference) do
      {:ok, %{status: status} = subscription}
      when status in [:active, :establishing, :recovering] ->
        id = Integer.to_string(state.next_id)

        frame = %{
          "version" => 1,
          "id" => id,
          "operation" => "unsubscribe",
          "parameters" => %{
            "subscription_id" => subscription.native_id,
            "generation" => subscription.generation
          },
          "timeout_ms" => @cleanup_timeout
        }

        if send_frame(state.port, frame) do
          state
          |> put_in([:subscriptions, reference, :status], :closing)
          |> put_in([:subscriptions, reference, :close_result], result)
          |> Map.put(:next_id, state.next_id + 1)
          |> Map.put(:internal_requests, Map.put(state.internal_requests, id, reference))
        else
          retire_subscription(state, reference)
        end

      _ ->
        state
    end
  end

  defp close_port(port) when is_port(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        # Reap the exact owned child before dropping its Port identity. A failed
        # native operation may leave the child unable to observe closed stdin.
        System.cmd("/bin/kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
        if Port.info(port), do: Port.close(port)

      nil ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp close_port(_), do: :ok

  defp await_close_exit(%{port: port, owner_monitor: monitor, call_deadline: deadline}) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, Error.new(:timeout)}
    else
      receive do
        {^port, {:exit_status, 0}} ->
          if System.monotonic_time(:millisecond) <= deadline,
            do: :ok,
            else: {:error, Error.new(:timeout)}

        {^port, {:exit_status, status}} ->
          {:error, Error.new(:invalid_transport_return, nil, %{exit_status: status})}

        {^port, {:data, _}} ->
          {:error, Error.new(:invalid_frame)}

        {:DOWN, ^monitor, :process, _, _} ->
          {:error, Error.new(:owner_closed)}
      after
        remaining -> {:error, Error.new(:timeout)}
      end
    end
  end

  defp emit_subscription(event, kind, result) do
    :telemetry.execute(
      [:wotex, :matter, :subscription, event],
      %{count: 1},
      %{kind: kind, result: result}
    )
  end
end
