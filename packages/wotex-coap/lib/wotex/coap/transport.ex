defmodule Wotex.CoAP.Transport do
  @moduledoc "Wotex Runtime adapter with an explicitly scoped CoAP socket and finite deadline."

  @behaviour Wotex.Runtime.Transport
  alias Wotex.CoAP.{Connection, Error, Mapping, RuntimeFrame, RuntimeRelay}
  alias Wotex.Runtime.{BindingProfile, Context, ExecutionContext, Request, Result}
  @unary_operations [:readproperty, :writeproperty, :invokeaction]

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{credential: nil}, config)
      when is_list(config) and request.operation in @unary_operations do
    now =
      if is_struct(request.deadline, DateTime),
        do: DateTime.utc_now(),
        else: System.monotonic_time(:millisecond)

    with :ok <- request_config(config),
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         {:ok, timeout} <-
           timeout(Context.remaining_ms(request.deadline, now), Keyword.get(config, :timeout, 5000)),
         deadline = System.monotonic_time(:millisecond) + timeout,
         connection_options =
           [host: mapping.host, port: mapping.port, timeout: timeout] ++
             Keyword.take(config, [:ack_timeout]),
         {:ok, pid} <- Connection.start_link(connection_options) do
      try do
        remaining = deadline - System.monotonic_time(:millisecond)

        with {:ok, reply} <-
               Connection.transfer(
                 pid,
                 mapping.message,
                 remaining,
                 Keyword.take(config, [:block_size, :max_body_size, :max_blocks])
               ),
             {:ok, value} <- Mapping.decode(mapping, reply),
             do:
               Result.new(request.request_id, request.operation, value,
                 metadata: %{code: reply.code}
               )
      after
        Connection.close(pid)
      end
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def subscribe(%Request{} = request, owner, %ExecutionContext{credential: nil} = execution, config)
      when is_pid(owner) and node(owner) == node() do
    with :ok <- stream_context(request, execution),
         :ok <- stream_config(config),
         true <- Process.alive?(owner),
         {:ok, deadline} <- deadline(request.deadline, Keyword.get(config, :timeout, 5000)),
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, nil, request.resolved_href),
         :ok <- stream_profile(request, mapping) do
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

  defp stream_context(
         %Request{input: nil} = request,
         %ExecutionContext{context: %Context{} = context} = execution
       )
       when map_size(request) == 10 and map_size(execution) == 3 and map_size(context) == 4 and
              request.operation in [:observeproperty, :subscribeevent] do
    expected_type = if request.operation == :observeproperty, do: :property, else: :event

    with {:ok, ^context} <-
           Context.new(
             request_id: context.request_id,
             deadline: context.deadline,
             metadata: context.metadata
           ),
         true <- request.request_id == context.request_id and request.deadline == context.deadline,
         true <- request.affordance_type == expected_type,
         true <- is_binary(request.resolved_href) and is_binary(request.affordance_name),
         do: :ok,
         else: (_ -> {:error, Error.new(:invalid_transport_context)})
  end

  defp stream_context(_, _), do: {:error, Error.new(:invalid_transport_context)}

  defp stream_profile(%Request{profile: %BindingProfile{} = profile} = request, mapping) do
    valid =
      BindingProfile.supports_scheme?(profile, "coap") and
        BindingProfile.supports_operation?(profile, request.operation) and
        BindingProfile.supports_media_type?(profile, Map.get(mapping.form.value, "contentType"))

    if valid, do: :ok, else: {:error, Error.new(:invalid_transport_context)}
  rescue
    _ -> {:error, Error.new(:invalid_transport_context)}
  end

  defp stream_profile(_, _), do: {:error, Error.new(:invalid_transport_context)}

  defp request_config(config) do
    with :ok <- validate_config(config),
         true <-
           not Keyword.has_key?(config, :renew) and not Keyword.has_key?(config, :max_queue_length),
         do: :ok,
         else: (_ -> {:error, Error.new(:invalid_options)})
  end

  defp stream_config(config) do
    with :ok <- validate_config(config),
         true <- Keyword.keys(config) -- [:timeout, :ack_timeout, :renew, :max_queue_length] == [],
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
            :max_queue_length
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
