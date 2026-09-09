defmodule Wotex.BACnet.BACstack do
  @moduledoc "BACstack 0.0.1 adapter over a borrowed, explicitly configured Client process."
  @behaviour Wotex.BACnet.Client
  alias BACnet.Protocol.{APDU, Constants}
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{Address, Error, OperationOwner, StackClient, StackOwner, Value, ValueBoundary}

  @impl Wotex.BACnet.Client
  def connect(opts) do
    with {:ok, config} <- configuration(opts), :ok <- verify_client(config), do: start_owner(config)
  end

  @doc false
  @spec connect_owned(term(), pid()) :: {:ok, map()} | {:error, Error.t()}
  def connect_owned(opts, stack) when is_pid(stack) do
    result =
      with {:ok, config} <- configuration(opts),
           config <- %{config | stack_client_kind: :wotex},
           :ok <- verify_client(config),
           do: start_owner(%{config | owned_stack: stack})

    case result do
      {:ok, _} ->
        result

      error ->
        StackOwner.close(stack)
        error
    end
  end

  defp verify_client(%{stack_client_kind: :wotex, client: client}),
    do: StackClient.verify(client, 100)

  defp verify_client(_), do: :ok

  defp start_owner(config) do
    config = Map.put(config, :generation, make_ref())

    case OperationOwner.start_link(config) do
      {:ok, owner} -> {:ok, Map.put(config, :owner, owner)}
      _ -> {:error, Error.new(:startup_failed)}
    end
  end

  @doc false
  @spec configuration(term()) :: {:ok, map()} | {:error, Error.t()}
  def configuration(opts) when is_list(opts) do
    if valid_options?(opts), do: connect_options(opts), else: {:error, Error.new(:invalid_options)}
  end

  def configuration(_), do: {:error, Error.new(:invalid_options)}

  defp connect_options(opts) do
    client = Keyword.get(opts, :stack_client)
    kind = Keyword.get(opts, :stack_client_kind, :bacstack)
    destination = Keyword.get(opts, :destination)
    writes = Keyword.get(opts, :writes, false)
    timeout = Keyword.get(opts, :timeout, 5000)

    peer =
      Keyword.get(opts, :peer_receive, %{
        max_apdu: 50,
        max_segments: 1,
        segmentation: :no_segmentation
      })

    receive_limits = Keyword.get(opts, :receive_limits)

    if is_pid(client) and Process.alive?(client) and kind in [:bacstack, :wotex] and
         valid_destination?(destination) and
         is_boolean(writes) and
         is_integer(timeout) and timeout in 1..60_000 and valid_peer?(peer) and
         receive_limits in [nil, %{max_apdu: 1476, max_segments: 32, max_bytes: 65_536}],
       do:
         {:ok,
          %{
            client: client,
            stack_client_kind: kind,
            destination: destination,
            writes: writes,
            peer_receive: peer,
            receive_limits: receive_limits,
            owned_stack: nil
          }},
       else: {:error, Error.new(:invalid_options)}
  end

  @impl Wotex.BACnet.Client
  def request(
        %{
          owner: owner,
          generation: generation,
          writes: writes,
          peer_receive: peer,
          destination: destination
        },
        message,
        timeout
      )
      when is_pid(owner) and is_reference(generation) and is_integer(timeout) and
             timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout

    with true <- valid_destination?(destination) and valid_peer?(peer),
         :ok <- Address.validate_message(message),
         {:ok, address} <- Address.new(message),
         {:ok, _} <- service(address, message, writes) do
      OperationOwner.request(owner, generation, message, deadline)
    else
      false -> {:error, Error.new(:invalid_options)}
      error -> error
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_request)}

  @doc false
  @spec exchange(map(), map(), integer()) :: {:ok, term()} | {:error, Error.t()}
  def exchange(config, message, deadline) do
    with :ok <- Address.validate_message(message),
         {:ok, address} <- Address.new(message),
         {:ok, apdu} <- service(address, message, config.writes),
         true <- System.monotonic_time(:millisecond) < deadline do
      peer = config.peer_receive

      options = [
        max_apdu_length: peer.max_apdu,
        max_segments: peer.max_segments,
        segmentation_supported: peer.segmentation
      ]

      result =
        if config.stack_client_kind == :wotex,
          do: StackClient.exchange(config.client, config.destination, apdu, options, deadline),
          else: BACnet.Stack.Client.send(config.client, config.destination, apdu, options)

      result
      |> response(address, message.type)
      |> effect(message.type)
    else
      false -> {:error, Error.new(:deadline_exceeded)}
      error -> error
    end
  rescue
    _ -> effect({:error, Error.new(:transport_error)}, message.type)
  catch
    :exit, _ -> effect({:error, Error.new(:connection_closed)}, message.type)
  end

  @impl Wotex.BACnet.Client
  def disconnect(%{owner: owner}), do: OperationOwner.close(owner)
  def disconnect(_), do: :ok

  defp effect({:error, %Error{details: %{dispatch: :not_started}}} = error, _), do: error

  defp effect({:error, error}, :write_property), do: {:error, %{error | effect: :unknown}}
  defp effect(result, _), do: result

  @doc "Accepts only an exact service acknowledgment; missing/negative responses fail."
  @spec response(term(), Address.t(), atom()) :: {:ok, term()} | {:error, Error.t()}
  def response(result, address, operation) do
    classify(result, address, operation)
  rescue
    _ -> {:error, Error.new(:invalid_response)}
  end

  defp classify({:ok, %APDU.ComplexACK{} = apdu}, address, :read_property) do
    with :ok <- ValueBoundary.validate(apdu.payload),
         {:ok, object, property, index, value} <- read_payload(apdu.payload),
         true <- apdu.service == :read_property,
         true <- object == <<address.object_type::10, address.instance::22>>,
         true <- :binary.decode_unsigned(property) == address.property,
         true <- index == address.array_index,
         {:ok, encoded} <- native_values(value),
         :ok <- Value.validate_read(encoded) do
      {:ok, encoded}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:response_mismatch)}
    end
  end

  defp classify({:ok, %APDU.SimpleACK{service: service}}, _, operation)
       when service == operation and
              operation in [:write_property, :subscribe_cov, :subscribe_cov_property],
       do: {:ok, if(operation == :write_property, do: :written, else: :subscribed)}

  defp classify({:ok, %APDU.Error{service: service, class: class, code: code}}, _, service),
    do:
      remote_error(:remote_error, %{
        class: numeric(:error_class, class),
        code: numeric(:error_code, code)
      })

  defp classify({:ok, %APDU.Abort{reason: reason}}, _, _),
    do: remote_error(:remote_abort, %{reason: numeric(:abort_reason, reason)})

  defp classify({:ok, %APDU.Reject{reason: reason}}, _, _),
    do: remote_error(:remote_reject, %{reason: numeric(:reject_reason, reason)})

  defp classify({:error, reason}, _, _) when reason in [:timeout, :apdu_timeout],
    do: {:error, Error.new(:deadline_exceeded)}

  defp classify({:error, %Error{}} = error, _, _), do: error

  defp classify({:error, _}, _, _), do: {:error, Error.new(:transport_error)}
  defp classify(_, _, _), do: {:error, Error.new(:missing_acknowledgment)}

  defp remote_error(code, details), do: {:error, Error.new(code, nil, details)}

  defp numeric(type, value) do
    number = Constants.by_name_atom(type, value)
    if is_integer(number) and number in 0..65_535, do: number, else: raise(ArgumentError)
  end

  defp read_payload([{:tagged, {0, <<_::32>> = object, 4}}, {:tagged, {1, property, len}} | tail])
       when is_binary(property) and byte_size(property) == len and len in 1..4 do
    case tail do
      [{:constructed, {3, value, 0}}] ->
        {:ok, object, property, nil, value}

      [{:tagged, {2, index, index_len}}, {:constructed, {3, value, 0}}]
      when is_binary(index) and byte_size(index) == index_len and index_len in 1..4 ->
        {:ok, object, property, :binary.decode_unsigned(index), value}

      _ ->
        :error
    end
  end

  defp read_payload(_), do: :error

  defp native_values(values) when is_list(values) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
        case Encoding.create(value) do
          {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
          _ -> {:halt, :error}
        end
      end)

    case result do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp native_values(value), do: Encoding.create(value)

  defp service(address, %{type: :read_property}, _),
    do: {:ok, request_apdu(:read_property, selectors(address))}

  defp service(address, %{type: :write_property, value: value}, true) do
    values =
      if is_list(value),
        do: Enum.map(value, &Value.to_tag/1),
        else: Value.to_tag(value)

    parameters =
      selectors(address) ++ [{:constructed, {3, values, 0}}] ++ optional_tag(4, address.priority)

    {:ok, request_apdu(:write_property, parameters)}
  end

  defp service(_, _, _), do: {:error, Error.new(:write_configuration_required)}

  defp selectors(address),
    do:
      [
        {:tagged, {0, <<address.object_type::10, address.instance::22>>, 4}},
        unsigned_tag(1, address.property)
      ] ++ optional_tag(2, address.array_index)

  defp optional_tag(_, nil), do: []
  defp optional_tag(tag, value), do: [unsigned_tag(tag, value)]

  defp unsigned_tag(tag, value) do
    bytes = :binary.encode_unsigned(value)
    {:tagged, {tag, bytes, byte_size(bytes)}}
  end

  defp request_apdu(service, parameters),
    do: %APDU.ConfirmedServiceRequest{
      segmented_response_accepted: true,
      max_segments: 32,
      max_apdu: 1476,
      invoke_id: 0,
      sequence_number: nil,
      proposed_window_size: nil,
      service: service,
      parameters: parameters
    }

  defp valid_peer?(%{max_apdu: apdu, max_segments: segments, segmentation: segmentation} = peer)
       when map_size(peer) == 3 and is_integer(apdu) and apdu in 50..1476 and
              is_integer(segments) and segments in 1..64 and
              segmentation in [
                :no_segmentation,
                :segmented_receive,
                :segmented_transmit,
                :segmented_both
              ],
       do: true

  defp valid_peer?(_), do: false

  defp valid_destination?({{a, b, c, d}, port}) when port in 1..65_535,
    do: Enum.all?([a, b, c, d], &(is_integer(&1) and &1 in 0..255))

  defp valid_destination?(_), do: false

  defp valid_options?(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)

      allowed = [
        :stack_client,
        :stack_client_kind,
        :destination,
        :writes,
        :timeout,
        :peer_receive,
        :receive_limits
      ]

      keys -- allowed == [] and
        length(keys) == MapSet.size(MapSet.new(keys))
    else
      false
    end
  end
end
