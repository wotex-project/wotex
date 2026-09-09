defmodule Wotex.CoAP.Transport do
  @moduledoc """
  Executes Wotex Runtime requests through an explicitly scoped CoAP socket.

  The transport validates the Runtime request and execution context, maps the
  selected Form through `Wotex.CoAP.Mapping`, spends one finite deadline across
  connection setup and exchange, decodes the reply, and closes the exact socket
  owner. Property observations and Event subscriptions use an explicitly owned
  relay process. The relay validates complete native reports and
  retains the exact subscription generation until cancellation or cleanup.

  ## Runtime boundary

  UDP routes reject credentials. DTLS routes require one validated
  `Wotex.CoAP.Security` value: unary calls accept either an immediate credential
  or the `:security` transport option, while subscriptions require the configured
  option and a nil immediate credential. Supplying both sources fails before
  acquisition. Scoped sessions close before the callback returns. Persistent
  native security custody is explicit configured state; handles contain no secret.
  Runtime Form selection does not authorize network access, and a
  successful CoAP response does not establish canonical Property truth or a
  physical Action effect. The consumer owns routing, authorization,
  supervision, security-layer selection, and any policy for interpreting
  returned protocol metadata.
  """

  @behaviour Wotex.Runtime.Transport
  alias Wotex.CoAP.{Connection, Error, Mapping, RuntimeFrame, RuntimeRelay, RuntimeSecurity}
  alias Wotex.Runtime.{BindingProfile, Context, ExecutionContext, Request, Result}
  @unary_operations [:readproperty, :writeproperty, :invokeaction]

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{} = execution, config)
      when is_list(config) and request.operation in @unary_operations do
    now =
      if is_struct(request.deadline, DateTime),
        do: DateTime.utc_now(),
        else: System.monotonic_time(:millisecond)

    with :ok <- request_config(config),
         :ok <- request_context(request, execution),
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         :ok <- mapping_profile(request, mapping),
         {:ok, security} <- RuntimeSecurity.options(mapping.scheme, execution.credential, config),
         {:ok, timeout} <-
           timeout(Context.remaining_ms(request.deadline, now), Keyword.get(config, :timeout, 5000)),
         deadline = System.monotonic_time(:millisecond) + timeout,
         connection_options =
           [host: mapping.host, port: mapping.port, timeout: timeout] ++
             security ++
             Keyword.take(config, [:ack_timeout]),
         {:ok, pid} <- Connection.start_link(connection_options) do
      scoped_request(pid, request, mapping, deadline, config)
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  defp scoped_request(pid, request, mapping, deadline, config) do
    result = execute_request(pid, request, mapping, deadline, config)

    case Connection.close(pid) do
      :ok ->
        with {:ok, _} <- result,
             :ok <- completion_deadline(deadline, mapping.message),
             do: result

      {:error, error} ->
        {:error, mutation_effect(error, mapping.message)}
    end
  catch
    kind, reason ->
      Connection.close(pid)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp execute_request(pid, request, mapping, deadline, config) do
    with remaining when remaining > 0 <- deadline - System.monotonic_time(:millisecond),
         {:ok, reply} <-
           Connection.transfer(
             pid,
             mapping.message,
             remaining,
             Keyword.take(config, [:block_size, :max_body_size, :max_blocks])
           ) do
      case Mapping.decode(mapping, reply) do
        {:ok, value} ->
          Result.new(request.request_id, request.operation, value, metadata: %{code: reply.code})

        {:error, error} ->
          {:error, mutation_effect(error, mapping.message)}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:deadline_exceeded)}
    end
  end

  defp completion_deadline(deadline, message) do
    if System.monotonic_time(:millisecond) < deadline,
      do: :ok,
      else: {:error, mutation_effect(Error.new(:deadline_exceeded), message)}
  end

  defp mutation_effect(error, message),
    do: Error.with_effect(error, if(message.code in [2, 3, 4], do: :unknown, else: :none))

  @impl Wotex.Runtime.Transport
  def subscribe(%Request{} = request, owner, %ExecutionContext{credential: nil} = execution, config)
      when is_pid(owner) and node(owner) == node() do
    with :ok <- stream_context(request, execution),
         :ok <- stream_config(config),
         true <- Process.alive?(owner),
         {:ok, deadline} <- deadline(request.deadline, Keyword.get(config, :timeout, 5000)),
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, nil, request.resolved_href),
         :ok <- mapping_profile(request, mapping),
         {:ok, security} <- RuntimeSecurity.options(mapping.scheme, nil, config) do
      RuntimeRelay.open(%{
        owner: owner,
        path: mapping.path,
        connection_options:
          [
            host: mapping.host,
            port: mapping.port,
            observation_kind: if(request.operation == :subscribeevent, do: :event, else: :property),
            observation_options: [accept: mapping.format, confirmable: mapping.message.type == :con]
          ] ++
            security ++
            Keyword.take(config, [:ack_timeout]),
        renew: Keyword.get(config, :renew, true),
        max_queue_length: Keyword.get(config, :max_queue_length, 1000),
        deadline: deadline
      })
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:invalid_transport_context)}
    end
  end

  def subscribe(_, _, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, _, _), do: RuntimeRelay.close(handle, stop_budget(request))

  defp stop_budget(%Request{deadline: value}) do
    case deadline(value, 1000) do
      {:ok, deadline} -> max(deadline - System.monotonic_time(:millisecond), 0)
      _ -> 0
    end
  end

  defp stop_budget(_), do: 1000

  @impl Wotex.Runtime.Transport
  def decode_frame({:value, message, metadata}, %Request{input: nil} = request, config)
      when request.operation in [:observeproperty, :subscribeevent] do
    with :ok <- stream_config(config),
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, nil, request.resolved_href),
         do: RuntimeFrame.decode(mapping, message, metadata)
  end

  def decode_frame({:error, error}, _, _), do: {:error, RuntimeFrame.error(error)}
  def decode_frame(_, _, _), do: :ignore

  defp stream_context(request, execution) do
    with :ok <- request_context(request, execution),
         true <- is_nil(request.input),
         do: :ok,
         else: (_ -> {:error, Error.new(:invalid_transport_context)})
  end

  defp request_context(
         %Request{} = request,
         %ExecutionContext{context: %Context{} = context} = execution
       )
       when map_size(request) == 10 and map_size(execution) == 3 and map_size(context) == 4 and
              request.operation in [
                :readproperty,
                :writeproperty,
                :invokeaction,
                :observeproperty,
                :subscribeevent
              ] do
    expected_type =
      case request.operation do
        :invokeaction -> :action
        :subscribeevent -> :event
        _ -> :property
      end

    with {:ok, ^context} <-
           Context.new(
             request_id: context.request_id,
             deadline: context.deadline,
             metadata: context.metadata
           ),
         true <- request.request_id == context.request_id and request.deadline == context.deadline,
         true <- request.affordance_type == expected_type,
         true <- is_binary(request.resolved_href) and is_binary(request.affordance_name),
         true <- valid_profile?(request.profile, request.operation),
         do: :ok,
         else: (_ -> {:error, Error.new(:invalid_transport_context)})
  end

  defp request_context(_, _), do: {:error, Error.new(:invalid_transport_context)}

  defp valid_profile?(profile, operation) do
    {:ok, observed} = Wotex.CoAP.profile(:udp_observe)
    {:ok, secured} = Wotex.CoAP.profile(:dtls)

    profile in [Wotex.CoAP.profile(), observed, secured] and
      BindingProfile.supports_operation?(profile, operation)
  end

  defp mapping_profile(%Request{profile: %BindingProfile{} = profile} = request, mapping) do
    valid =
      BindingProfile.supports_scheme?(profile, Atom.to_string(mapping.scheme)) and
        BindingProfile.supports_operation?(profile, request.operation) and
        BindingProfile.supports_media_type?(profile, Map.get(mapping.form.value, "contentType"))

    if valid, do: :ok, else: {:error, Error.new(:invalid_transport_context)}
  rescue
    _ -> {:error, Error.new(:invalid_transport_context)}
  end

  defp mapping_profile(_, _), do: {:error, Error.new(:invalid_transport_context)}

  defp request_config(config) do
    with :ok <- validate_config(config),
         true <-
           not Keyword.has_key?(config, :renew) and not Keyword.has_key?(config, :max_queue_length),
         do: :ok,
         else: (_ -> {:error, Error.new(:invalid_options)})
  end

  defp stream_config(config) do
    with :ok <- validate_config(config),
         true <-
           Keyword.keys(config) -- [:timeout, :ack_timeout, :renew, :max_queue_length, :security] ==
             [],
         do: :ok,
         else: (_ -> {:error, Error.new(:invalid_options)})
  end

  defp deadline(value, maximum) do
    now =
      if is_struct(value, DateTime),
        do: DateTime.utc_now(),
        else: System.monotonic_time(:millisecond)

    with {:ok, timeout} <- timeout(Context.remaining_ms(value, now), maximum),
         do: {:ok, System.monotonic_time(:millisecond) + timeout}
  rescue
    _ -> {:error, Error.new(:invalid_transport_context)}
  end

  defp timeout(:infinity, max) when is_integer(max) and max in 1..60_000, do: {:ok, max}

  defp timeout(left, max)
       when is_integer(left) and left > 0 and is_integer(max) and max in 1..60_000,
       do: {:ok, min(left, max)}

  defp timeout(_, _), do: {:error, Error.new(:deadline_exceeded)}

  defp validate_config(config) do
    if Keyword.keyword?(config) do
      keys = Keyword.keys(config)

      cond do
        keys --
          [
            :timeout,
            :ack_timeout,
            :block_size,
            :max_body_size,
            :max_blocks,
            :renew,
            :max_queue_length,
            :security
          ] != [] ->
          {:error, Error.new(:invalid_options)}

        length(keys) != MapSet.size(MapSet.new(keys)) ->
          {:error, Error.new(:invalid_options)}

        Keyword.has_key?(config, :ack_timeout) and
            Keyword.get(config, :ack_timeout) not in 1..3000 ->
          {:error, Error.new(:invalid_ack_timeout)}

        not is_boolean(Keyword.get(config, :renew, true)) or
            Keyword.get(config, :max_queue_length, 1000) not in 1..10_000 ->
          {:error, Error.new(:invalid_observation_options)}

        true ->
          case Wotex.CoAP.Blockwise.config(
                 Keyword.take(config, [:block_size, :max_body_size, :max_blocks])
               ) do
            {:ok, _} -> :ok
            error -> error
          end
      end
    else
      {:error, Error.new(:invalid_options)}
    end
  end
end
