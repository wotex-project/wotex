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

  alias Wotex.Matter.Error
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
               next_id: 2
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

  def handle_info({port, {:exit_status, _}}, %{port: port} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: {:stop, :normal, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) when is_map(state) do
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
      case await_response(state.port, state.owner_monitor, id, timeout + @response_grace) do
        {:ok, result} -> {:ok, result, next_state}
        {:error, error} -> {:error, error, next_state}
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
         {:ok, _} <- await_response(port, owner_monitor, "1", options.timeout) do
      :ok
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:controller_start_failed)}
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

  defp await_response(port, owner_monitor, id, timeout) do
    with {:ok, line} <- await_line(port, owner_monitor, timeout),
         {:ok, frame} <- Jason.decode(line) do
      decode_response(frame, id)
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_frame)}
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

  defp decode_response(_, _), do: {:error, Error.new(:invalid_frame)}

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

  defp close_port(port) when is_port(port) do
    Port.close(port)
  rescue
    _ -> :ok
  end

  defp close_port(_), do: :ok
end
