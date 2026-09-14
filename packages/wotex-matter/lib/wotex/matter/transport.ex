defmodule Wotex.Matter.Transport do
  @moduledoc """
  Executes Wotex Runtime requests through a scoped Matter client session.

  The transport accepts Runtime request and execution-context structs, maps the
  selected Form through `Wotex.Matter.Mapping`, opens the configured client,
  performs one read, write, or invoke, and closes the exact session. Requests
  selected through the controller profile use typed standalone services.
  Controller observations and Event subscriptions use a private relay that owns
  the native session and translates validated reports for Runtime.

  ## Runtime boundary

  A concrete fabric-scoped path is required, and its fabric identity must match
  the configured target. Credentials are rejected because
  this adapter contract keeps them inside the consumer-owned controller.
  Runtime Form selection is not authorization, and successful protocol
  completion does not establish canonical Property truth or a physical Action
  effect. The consumer owns commissioning, trust policy, deadlines,
  supervision, data-model validation, and interpretation of protocol results.
  """
  @behaviour Wotex.Runtime.Transport
  alias Wotex.Matter
  alias Wotex.Matter.{Address, AttributeReport, Descriptor, Error, Mapping, RuntimeRelay}
  alias Wotex.Runtime.{BindingProfile, Context, ExecutionContext, Request, Result}
  @max_baseline_message_bytes 131_072

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{credential: nil}, config)
      when is_list(config) do
    with true <- Keyword.keyword?(config),
         true <- request.operation in [:readproperty, :writeproperty, :invokeaction],
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         :ok <- preflight(request, mapping),
         {:ok, timeout} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)) do
      deadline = System.monotonic_time(:millisecond) + timeout

      options =
        config
        |> client_options()
        |> Keyword.put(:timeout, timeout)

      Matter.with_connection(options, fn session ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if controller?(request),
          do: execute_controller(session, mapping, request, remaining),
          else: execute(session, mapping.message, request, remaining)
      end)
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:target_mismatch)}
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def subscribe(
        %Request{} = request,
        owner,
        %ExecutionContext{credential: nil},
        config
      )
      when is_pid(owner) and is_list(config) do
    with true <- Process.alive?(owner),
         true <- Keyword.keyword?(config),
         true <- controller?(request),
         true <- request.operation in [:observeproperty, :subscribeevent],
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, timeout} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)),
         {:ok, address} <- address(mapping.message),
         :ok <- stream_preflight(mapping.kind, address),
         {:ok, stream_options} <- stream_options(config) do
      options =
        config
        |> client_options()
        |> Keyword.put(:timeout, timeout)

      RuntimeRelay.start(
        owner,
        request.request_id,
        request.operation,
        mapping.kind,
        address,
        options,
        stream_options,
        timeout
      )
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_context)}
    end
  end

  def subscribe(_, _, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, %Request{}, %ExecutionContext{}, _),
    do: RuntimeRelay.close(handle)

  def unsubscribe(handle, _, _, _), do: RuntimeRelay.close(handle)

  @impl Wotex.Runtime.Transport
  def decode_frame(frame, %Request{} = request, config) when is_list(config) do
    with true <- Keyword.keyword?(config),
         true <- request.operation in [:observeproperty, :subscribeevent],
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, address} <- address(mapping.message) do
      RuntimeRelay.decode(frame, request.request_id, request.operation, mapping.kind, address)
    else
      _ -> :ignore
    end
  end

  def decode_frame(_, _, _), do: :ignore

  defp execute(session, message, request, remaining) when remaining > 0 do
    with {:ok, value} <- Matter.send(%{session | timeout: remaining}, message),
         do: Result.new(request.request_id, request.operation, value)
  end

  defp execute(_, _, _, _), do: {:error, Error.new(:deadline_exceeded)}

  defp execute_controller(_, _, _, remaining) when remaining <= 0,
    do: {:error, Error.new(:deadline_exceeded)}

  defp execute_controller(session, %{message: message}, request, remaining) do
    with {:ok, address} <- address(message) do
      session = %{session | timeout: remaining}

      case request.operation do
        :readproperty -> controller_read(session, address, request)
        :writeproperty -> controller_write(session, address, request.input, request)
        :invokeaction -> controller_invoke(session, address, request.input, request)
        _ -> {:error, Error.new(:unsupported_operation)}
      end
    end
  end

  defp controller_read(session, address, request) do
    with {:ok, %AttributeReport{} = report} <- Matter.read_attribute(session, address),
         do:
           Result.new(request.request_id, request.operation, report.value,
             metadata: %{
               matter_kind: :attribute,
               path: Map.from_struct(report.path),
               status: 0,
               data_version: report.data_version
             }
           )
  end

  defp controller_write(session, address, input, request) do
    with {:ok, %{path: path, status: 0}} <- Matter.write_attribute(session, address, input),
         {:ok, ^address} <- Address.new(path),
         do:
           Result.new(request.request_id, request.operation, :written,
             metadata: %{
               matter_kind: :attribute,
               path: Map.from_struct(address),
               status: 0
             }
           )
  end

  defp controller_invoke(session, address, input, request) do
    with {:ok, %{path: response_path, value: value, status: 0}} <-
           Matter.invoke_command(session, address, input),
         {:ok, response_path} <- response_path(response_path) do
      Result.new(request.request_id, request.operation, value,
        metadata: %{
          matter_kind: :command,
          path: Map.from_struct(address),
          response_path: response_path,
          status: 0
        }
      )
    end
  end

  defp response_path(nil), do: {:ok, nil}

  defp response_path(path) do
    with {:ok, path} <- Address.new(path), do: {:ok, Map.from_struct(path)}
  end

  defp address(message) do
    message
    |> Map.take([:fabric_id, :node_id, :endpoint, :cluster, :member])
    |> Address.new()
  end

  defp preflight(%Request{} = request, %{message: message}) do
    with :ok <- Address.validate_message(message),
         {:ok, address} <- address(message) do
      if controller?(request),
        do: controller_input(request.operation, address, request.input),
        else: baseline_input(request.operation, message)
    end
  end

  defp controller_input(:readproperty, address, _),
    do: descriptor(Descriptor.lookup(:attribute, address, :read))

  defp controller_input(:writeproperty, address, input),
    do: descriptor(Descriptor.validate_element(:attribute, address, :write, input))

  defp controller_input(:invokeaction, address, input),
    do: descriptor(Descriptor.validate_element(:command, address, :invoke, input))

  defp descriptor({:ok, _}), do: :ok
  defp descriptor({:error, %Error{}} = error), do: error

  defp baseline_input(operation, message) when operation in [:writeproperty, :invokeaction] do
    case Jason.encode(message) do
      {:ok, encoded} when byte_size(encoded) < @max_baseline_message_bytes -> :ok
      _ -> {:error, Error.new(:invalid_value)}
    end
  end

  defp baseline_input(:readproperty, _), do: :ok

  defp stream_preflight(:attribute, address),
    do: descriptor(Descriptor.lookup(:attribute, address, :subscribe))

  defp stream_preflight(:event, address),
    do: descriptor(Descriptor.lookup(:event, address, :subscribe))

  defp controller?(%Request{profile: %BindingProfile{} = profile}),
    do: BindingProfile.id(profile) == :matter_controller

  defp controller?(_), do: false

  defp client_options(config),
    do: Keyword.drop(config, [:target, :subscription_options])

  defp stream_options(config) do
    case Keyword.get(config, :subscription_options, []) do
      options when is_list(options) ->
        if Keyword.keyword?(options),
          do: {:ok, options},
          else: {:error, Error.new(:invalid_subscription)}

      _ ->
        {:error, Error.new(:invalid_subscription)}
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
