defmodule Wotex.Modbus.Transport do
  @moduledoc "Wotex Runtime transport that scopes one TCP session to one bounded interaction."

  @behaviour Wotex.Runtime.Transport
  alias Wotex.Modbus.{Error, Mapping}
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{credential: nil}, config)
      when is_list(config) do
    with {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input,
             base: request.resolved_href
           ),
         {:ok, timeout} <- timeout(request.deadline, Keyword.get(config, :timeout, 5000)),
         deadline = System.monotonic_time(:millisecond) + timeout,
         opts =
           Map.to_list(mapping.endpoint) ++
             [unit_id: mapping.command.address.unit_id, timeout: timeout] ++
             Keyword.take(config, [:security]),
         {:ok, session} <- Wotex.Modbus.connect(opts) do
      try do
        with {:ok, raw} <- execute(session, mapping.command, deadline),
             {:ok, value} <- Mapping.decode(mapping, raw) do
          Result.new(request.request_id, request.operation, value,
            metadata: %{function: mapping.command.function}
          )
        end
      after
        Wotex.Modbus.disconnect(session)
      end
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  defp execute(session, command, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0,
      do: Wotex.Modbus.Connection.request(session.pid, command, remaining),
      else: {:error, Error.new(:deadline_exceeded)}
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
end
