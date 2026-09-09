defmodule Wotex.Modbus.Transport do
  @moduledoc """
  Executes one Wotex Runtime interaction through one scoped Modbus TCP session.

  The transport validates the Runtime request and execution context, maps the
  selected Form through `Wotex.Modbus.Mapping`, opens a connection to the mapped
  endpoint, performs the exact command, converts its result, and closes the
  session. Subscription callbacks return explicit unsupported errors because
  this profile does not create a polling or push process.

  ## Runtime boundary

  Credentials are rejected because classic Modbus TCP in this package defines
  no credential transport. Runtime Form selection is not authorization, and a
  successful response does not establish canonical Property truth or a physical
  Action effect. The consumer owns routing, authorization, deadlines,
  supervision, Modbus Security where required, and any policy for interpreting
  returned register values.
  """

  @behaviour Wotex.Runtime.Transport
  alias Wotex.Form
  alias Wotex.Modbus.{Command, Error, Mapping}
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{credential: nil}, config) do
    with :ok <- validate_config(config),
         :ok <- request_shape(request),
         {:ok, timeout} <- timeout(request.deadline, Keyword.get(config, :timeout, 5000)),
         deadline = System.monotonic_time(:millisecond) + timeout,
         {:ok, mapping} <- route(request),
         {:ok, remaining} <- remaining(deadline),
         opts =
           Map.to_list(mapping.endpoint) ++
             [unit_id: mapping.command.address.unit_id, timeout: remaining] ++
             Keyword.take(config, [:security]),
         {:ok, session} <- Wotex.Modbus.connect(opts) do
      scoped_request(session, request, mapping, deadline)
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  defp scoped_request(session, request, mapping, deadline) do
    result = execute(session, request, mapping, deadline)

    case Wotex.Modbus.disconnect(session) do
      :ok ->
        with {:ok, _} <- result,
             :ok <- completion_deadline(deadline, mapping.command),
             do: result

      {:error, error} ->
        {:error, mutation_effect(error, mapping.command)}
    end
  catch
    kind, reason ->
      Wotex.Modbus.disconnect(session)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp execute(session, request, mapping, deadline) do
    with {:ok, remaining} <- remaining(deadline),
         {:ok, raw} <- Wotex.Modbus.Connection.request(session.pid, mapping.command, remaining),
         {:ok, value} <- Mapping.decode(mapping, raw),
         :ok <- completion_deadline(deadline, mapping.command) do
      Result.new(request.request_id, request.operation, value,
        metadata: %{function: mapping.command.function}
      )
    end
  end

  defp completion_deadline(deadline, command) do
    case remaining(deadline) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, mutation_effect(error, command)}
    end
  end

  defp mutation_effect(error, command),
    do: Error.with_effect(error, if(Command.write?(command), do: :unknown, else: :none))

  defp request_shape(request) do
    valid_context =
      {request.affordance_type, request.operation} in [
        {:property, :readproperty},
        {:property, :writeproperty},
        {:action, :invokeaction}
      ]

    if valid_context and request.profile == Wotex.Modbus.profile() and
         is_binary(request.resolved_href) do
      case Result.new(request.request_id, request.operation, nil) do
        {:ok, _} -> :ok
        {:error, _} -> {:error, Error.new(:invalid_request)}
      end
    else
      {:error, Error.new(:invalid_request)}
    end
  end

  defp route(%Request{form: %Form{value: value}} = request)
       when is_map(value) and not is_struct(value) do
    with {:ok, form} <- Form.new(value, for: request.affordance_type),
         resolved = Map.put(Form.to_map(form), "href", request.resolved_href),
         {:ok, mapping} <- Mapping.command(resolved, request.operation, request.input) do
      {:ok, %{mapping | form: form}}
    else
      {:error, %Error{}} = error -> error
      {:error, _} -> {:error, Error.new(:invalid_form)}
    end
  end

  defp route(_), do: {:error, Error.new(:invalid_form)}

  defp remaining(deadline) do
    value = deadline - System.monotonic_time(:millisecond)
    if value > 0, do: {:ok, value}, else: {:error, Error.new(:deadline_exceeded)}
  end

  defp timeout(deadline, maximum) when is_integer(maximum) and maximum in 1..60_000 do
    now =
      if is_struct(deadline, DateTime),
        do: DateTime.utc_now(),
        else: System.monotonic_time(:millisecond)

    case Context.remaining_ms(deadline, now) do
      :infinity -> {:ok, maximum}
      0 -> {:error, Error.new(:deadline_exceeded)}
      remaining when is_integer(remaining) -> {:ok, min(remaining, maximum)}
      _ -> {:error, Error.new(:invalid_deadline)}
    end
  end

  defp timeout(_, _), do: {:error, Error.new(:invalid_timeout)}

  defp validate_config(config) do
    with :ok <- options(config, %{}) do
      if Keyword.get(config, :security, :none) == :none,
        do: :ok,
        else: {:error, Error.new(:unsupported_security, :security)}
    end
  end

  defp options([], _), do: :ok

  defp options([{key, _} | rest], seen)
       when key in [:timeout, :security] and not is_map_key(seen, key),
       do: options(rest, Map.put(seen, key, true))

  defp options(_, _), do: {:error, Error.new(:invalid_options)}
end
