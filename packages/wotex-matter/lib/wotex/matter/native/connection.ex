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
    case GenServer.start(__MODULE__, {owner, options}) do
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

  @spec disconnect(pid(), String.t()) :: :ok | {:error, Error.t()}
  def disconnect(pid, generation) do
    if Process.alive?(pid) do
      case call(pid, {:disconnect, generation}, @cleanup_timeout) do
        {:ok, nil} -> :ok
        {:error, _} = error -> error
      end
    else
      :ok
    end
  end

  @impl GenServer
  def init({owner, options}) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(owner)
    generation = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    case open_port(options.executable) do
      {:ok, port} ->
        case handshake(port, owner_monitor, generation, options) do
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
  def handle_call(:identity, _, state),
    do: {:reply, {:ok, state.generation}, state}

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

        execute(state, operation, parameters, timeout)
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
          receiver: receiver,
          monitor: monitor,
          queue_limit: request.queue_limit,
          kind: request.kind,
          paths: request.paths,
          status: :establishing,
          close_result: :cancelled,
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

          {:error, %Error{code: :timeout} = error, next_state} ->
            {:stop, :normal, {:error, error}, drop_subscription(next_state, reference)}

          {:error, error, next_state} ->
            {:reply, {:error, error}, drop_subscription(next_state, reference)}
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

          {:error, %Error{code: :timeout} = error, next_state} ->
            {:stop, :normal, {:error, error}, next_state}

          {:error, error, next_state} ->
            {:reply, {:error, error}, next_state}
        end
      end
    else
      _ -> {:reply, {:error, Error.new(:invalid_handle)}, state}
    end
  end

  def handle_call({:disconnect, generation}, _, state) do
    if generation == state.generation do
      case request_frame(state, "close", %{}, @cleanup_timeout) do
        {:ok, result, next_state} -> {:stop, :normal, {:ok, result}, next_state}
        {:error, error, next_state} -> {:stop, :normal, {:error, error}, next_state}
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

      {:error, %Error{code: :timeout} = error, next_state} ->
        {:stop, :normal, {:error, error}, next_state}

      {:error, error, next_state} ->
        {:reply, {:error, error}, next_state}
    end
  end

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

    if send_frame(state.port, frame) do
      case await_response(next_state, id, timeout + @response_grace) do
        {:ok, result, response_state} -> {:ok, result, response_state}
        {:error, error, response_state} -> {:error, error, response_state}
      end
    else
      {:error, Error.new(:transport_closed), next_state}
    end
  end

  defp call(pid, message, timeout) do
    GenServer.call(pid, message, timeout + 100)
  catch
    :exit, {:timeout, _} -> {:error, Error.new(:timeout)}
    :exit, _ -> {:error, Error.new(:transport_closed)}
  end

  defp open_port(executable) do
    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [:binary, :exit_status, :use_stdio, {:line, @maximum_line_bytes}]
      )

    {:ok, port}
  rescue
    _ -> {:error, Error.new(:controller_start_failed)}
  end

  defp handshake(port, owner_monitor, generation, options) do
    with :ok <- await_ready(port, owner_monitor, options.timeout),
         true <- send_frame(port, flow_frame(generation)),
         true <- send_frame(port, open_frame(options)),
         {:ok, _} <- handshake_response(port, owner_monitor, "1", options.timeout) do
      :ok
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:controller_start_failed)}
    end
  end

  defp handshake_response(port, owner_monitor, id, timeout) do
    with {:ok, line} <- await_line(port, owner_monitor, timeout),
         {:ok, frame} <- Jason.decode(line) do
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

  defp await_ready(port, owner_monitor, timeout) do
    case await_line(port, owner_monitor, timeout) do
      {:ok, line} ->
        with {:ok, frame} <- Jason.decode(line),
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

  defp await_response(state, id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_response_until(state, id, deadline)
  end

  defp await_response_until(state, id, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    with true <- remaining > 0,
         {:ok, line} <- await_line(state.port, state.owner_monitor, remaining),
         {:ok, frame} <- Jason.decode(line) do
      case decode_response(frame, id) do
        {:ok, result} ->
          {:ok, result, state}

        {:error, %Error{} = error} ->
          {:error, error, state}

        :not_response ->
          case decode_async_frame(frame, byte_size(line) + 1, state) do
            {:ok, next_state} -> await_response_until(next_state, id, deadline)
            {:error, error} -> {:error, error, state}
          end
      end
    else
      false -> {:error, Error.new(:timeout), state}
      {:error, %Error{} = error} -> {:error, error, state}
      _ -> {:error, Error.new(:invalid_frame), state}
    end
  end

  defp await_line(port, owner_monitor, timeout) do
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
      timeout -> {:error, Error.new(:timeout)}
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
    with {:ok, frame} <- Jason.decode(line) do
      decode_async_frame(frame, byte_size(line) + 1, state)
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
         {:ok, reference} <- Map.fetch(state.subscription_ids, key),
         %{status: :closing, last_report_sequence: expected_last} <-
           Map.fetch!(state.subscriptions, reference),
         true <- last_sequence == expected_last do
      retired =
        state
        |> consume_retired_reports(reference)
        |> retire_subscription(reference)

      {:ok, retired}
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
         true <- status in [:active, :establishing] do
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

  defp stringify_keys(map),
    do: Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)

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
      generation: generation
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

  defp drop_subscription(state, reference) do
    case Map.pop(state.subscriptions, reference) do
      {nil, _} ->
        state

      {subscription, subscriptions} ->
        Process.demonitor(subscription.monitor, [:flush])
        key = {subscription.native_id, subscription.generation}

        %{
          state
          | subscriptions: subscriptions,
            subscription_ids: Map.delete(state.subscription_ids, key),
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
          {:ok, current} when current.generation == subscription.generation -> :ok
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
      {:ok, %{status: status} = subscription} when status in [:active, :establishing] ->
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
    Port.close(port)
  rescue
    _ -> :ok
  end

  defp close_port(_), do: :ok

  defp emit_subscription(event, kind, result) do
    :telemetry.execute(
      [:wotex, :matter, :subscription, event],
      %{count: 1},
      %{kind: kind, result: result}
    )
  end
end
