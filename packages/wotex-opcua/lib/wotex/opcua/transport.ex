defmodule Wotex.OPCUA.Transport do
  @moduledoc """
  Executes Wotex Runtime requests through a scoped OPC UA client session.

  The transport validates the Runtime request and execution context, maps the
  selected Form through `Wotex.OPCUA.Mapping`, opens the configured client,
  performs one read or write, normalizes the result, and closes the exact
  session.

  `subscribe/4` accepts only `observeproperty` with nil input and a nil
  credential. After the Form target matches `:target`, it starts one
  `Wotex.OPCUA.RuntimeRelay` for the Runtime owner pid. The relay opens its own
  Session with the remaining options and one Value MonitoredItem. The optional
  `:subscription` map supplies S04 interval, queue, discard, keepalive and
  lifetime parameters, and `:max_queue_length` (default 1000, 1..10000) bounds
  the owner's queue. `subscribeevent` returns `unsupported_operation` without
  starting a process. `decode_frame/3` validates observation metadata and
  projects a native DataValue with `Wotex.OPCUA.Value.native_result/1`.
  `unsubscribe/4` releases the relay; a stopped relay returns `:ok`.
  For an explicitly selected native client, it converts the Form mapper's
  validated scalar or flat-array ByteString base64 back to raw bytes before
  a typed Value Write.

  ## Runtime boundary

  Credentials are rejected at this boundary because the client configuration
  owns the secure-channel material. Runtime Form selection is not
  authorization, and successful service completion does not establish canonical
  Property truth or a physical effect. The consumer owns endpoint policy,
  credential provisioning, deadlines, supervision, data-model validation, and
  interpretation of returned status metadata.

  Every error returned to Runtime passes through `Wotex.OPCUA.Error.classify/1`,
  so Runtime retry decisions see the finite class while native details and effect
  stay on the library Error.
  """
  @behaviour Wotex.Runtime.Transport
  alias Wotex.OPCUA
  alias Wotex.OPCUA.{Address, Error, Mapping, RuntimeRelay, Value}
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

  @impl Wotex.Runtime.Transport
  def request(request, execution, config),
    do: classified(run_request(request, execution, config))

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, execution, config),
    do: classified(run_subscribe(request, owner, execution, config))

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, execution, config),
    do: classified(run_unsubscribe(handle, request, execution, config))

  @impl Wotex.Runtime.Transport
  def decode_frame(frame, request, config), do: classified(run_decode_frame(frame, request, config))

  defp classified({:error, %Error{} = error}), do: {:error, Error.classify(error)}
  defp classified(result), do: result

  defp run_request(%Request{operation: operation}, %ExecutionContext{credential: nil}, _)
       when operation not in [:readproperty, :writeproperty],
       do: {:error, Error.new(:unsupported_operation)}

  defp run_request(%Request{} = request, %ExecutionContext{credential: nil}, config)
       when is_list(config) do
    with true <- Keyword.keyword?(config),
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, timeout} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)) do
      deadline = System.monotonic_time(:millisecond) + timeout

      options =
        config
        |> Keyword.delete(:target)
        |> Keyword.put(:timeout, timeout)

      OPCUA.with_connection(options, fn session ->
        remaining = deadline - System.monotonic_time(:millisecond)
        execute(session, mapping.message, request, remaining)
      end)
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:target_mismatch)}
    end
  end

  defp run_request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @stream_parameters [
    :publishing_interval_ms,
    :sampling_interval_ms,
    :queue_size,
    :discard_oldest,
    :keepalive_count,
    :lifetime_count
  ]
  @observation_metadata %{
    "sequence" => :sequence,
    "publish_time" => :publish_time,
    "client_handle" => :client_handle,
    "overflow" => :overflow,
    "datetime_resolution_ns" => :datetime_resolution_ns,
    "raw_datetime_ticks_available" => :raw_datetime_ticks_available
  }

  defp run_subscribe(%Request{operation: :subscribeevent}, _, _, _),
    do: {:error, Error.new(:unsupported_operation)}

  defp run_subscribe(
         %Request{operation: :observeproperty, input: nil} = request,
         owner,
         %ExecutionContext{credential: nil},
         config
       )
       when is_pid(owner) and node(owner) == node() and is_list(config) do
    with true <- Keyword.keyword?(config) and Process.alive?(owner),
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, nil, request.resolved_href),
         :ok <- target(config, mapping),
         {:ok, parameters} <- stream_parameters(Keyword.get(config, :subscription, %{})),
         {:ok, max_queue_length} <- max_queue_length(Keyword.get(config, :max_queue_length, 1000)),
         {:ok, timeout} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)) do
      RuntimeRelay.open(%{
        owner: owner,
        node_id: Address.to_string(mapping.message.node_id),
        parameters: parameters,
        max_queue_length: max_queue_length,
        connection: Keyword.drop(config, [:target, :subscription, :max_queue_length]),
        deadline: System.monotonic_time(:millisecond) + timeout
      })
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_context)}
    end
  end

  defp run_subscribe(_, _, _, _), do: {:error, Error.new(:invalid_transport_context)}

  defp run_unsubscribe(handle, _, %ExecutionContext{credential: nil}, _),
    do: RuntimeRelay.close(handle)

  defp run_unsubscribe(handle, _, _, _) do
    with :ok <- RuntimeRelay.close(handle), do: {:error, Error.new(:invalid_transport_context)}
  end

  defp run_decode_frame({:value, value, metadata}, %Request{operation: :observeproperty}, _) do
    with {:ok, observed} <- observation_metadata(metadata),
         {:ok, payload, projected} <- Value.native_result(value),
         do: {:ok, payload, Map.merge(projected, observed)}
  end

  defp run_decode_frame({:error, %Error{} = error}, _, _), do: {:error, error}
  defp run_decode_frame(_, _, _), do: :ignore

  defp target(config, mapping) do
    if Keyword.get(config, :target) == mapping.target,
      do: :ok,
      else: {:error, Error.new(:target_mismatch)}
  end

  defp stream_parameters(parameters) when is_map(parameters) do
    if Enum.all?(Map.keys(parameters), &(&1 in @stream_parameters)),
      do: {:ok, parameters},
      else: {:error, Error.new(:invalid_value)}
  end

  defp stream_parameters(_), do: {:error, Error.new(:invalid_value)}

  defp max_queue_length(value) when is_integer(value) and value in 1..10_000, do: {:ok, value}
  defp max_queue_length(_), do: {:error, Error.new(:invalid_value)}

  defp observation_metadata(metadata) when is_map(metadata) and map_size(metadata) == 6 do
    Enum.reduce_while(metadata, {:ok, %{}}, fn {key, value}, {:ok, observed} ->
      case Map.fetch(@observation_metadata, key) do
        {:ok, atom} -> {:cont, {:ok, Map.put(observed, atom, value)}}
        :error -> {:halt, {:error, Error.new(:invalid_native_frame)}}
      end
    end)
  end

  defp observation_metadata(_), do: {:error, Error.new(:invalid_native_frame)}

  defp execute(session, message, request, remaining) when remaining > 0 do
    with {:ok, message} <- native_message(session, message),
         {:ok, value} <- OPCUA.send(%{session | timeout: remaining}, message),
         {:ok, payload, metadata} <- Value.result(value),
         do: Result.new(request.request_id, request.operation, payload, metadata: metadata)
  end

  defp execute(_, _, _, _), do: {:error, Error.new(:deadline_exceeded)}

  defp native_message(
         %OPCUA.Session{client: Wotex.OPCUA.Open62541},
         %{type: :write, value: %{type: "ByteString", array: true, value: encoded}} = message
       )
       when is_list(encoded) do
    result =
      Enum.reduce_while(encoded, {:ok, []}, fn item, {:ok, bytes} ->
        case decode_byte(item) do
          {:ok, value} -> {:cont, {:ok, [value | bytes]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, bytes} -> {:ok, put_in(message.value.value, Enum.reverse(bytes))}
      error -> error
    end
  end

  defp native_message(
         %OPCUA.Session{client: Wotex.OPCUA.Open62541},
         %{type: :write, value: %{type: "ByteString", value: encoded}} = message
       )
       when is_binary(encoded) do
    case decode_byte(encoded) do
      {:ok, bytes} -> {:ok, put_in(message.value.value, bytes)}
      error -> error
    end
  end

  defp native_message(_, message), do: {:ok, message}

  defp decode_byte(nil), do: {:ok, nil}

  defp decode_byte(encoded) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, Error.new(:invalid_bytestring)}
    end
  end

  defp budget(deadline, max) when is_integer(max) and max in 1..60_000 do
    now =
      if is_struct(deadline, DateTime),
        do: DateTime.utc_now(),
        else: System.monotonic_time(:millisecond)

    case Context.remaining_ms(deadline, now) do
      :infinity -> {:ok, max}
      left when is_integer(left) and left > 0 -> {:ok, min(left, max)}
      _ -> {:error, Error.new(:deadline_exceeded)}
    end
  end

  defp budget(_, _), do: {:error, Error.new(:invalid_timeout)}
end
