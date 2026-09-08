defmodule Wotex.CoAP.Transport do
  @moduledoc "Wotex Runtime adapter with an explicitly scoped CoAP socket and finite deadline."

  @behaviour Wotex.Runtime.Transport
  alias Wotex.CoAP.{Connection, Error, Mapping}
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{credential: nil}, config)
      when is_list(config) do
    now =
      if is_struct(request.deadline, DateTime),
        do: DateTime.utc_now(),
        else: System.monotonic_time(:millisecond)

    with {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         {:ok, timeout} <-
           timeout(Context.remaining_ms(request.deadline, now), Keyword.get(config, :timeout, 5000)),
         deadline = System.monotonic_time(:millisecond) + timeout,
         {:ok, pid} <-
           Connection.start_link(host: mapping.host, port: mapping.port, timeout: timeout) do
      try do
        remaining = deadline - System.monotonic_time(:millisecond)

        with {:ok, reply} <- Connection.request(pid, mapping.message, remaining),
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
  def subscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  defp timeout(:infinity, max) when is_integer(max) and max in 1..60_000, do: {:ok, max}

  defp timeout(left, max)
       when is_integer(left) and left > 0 and is_integer(max) and max in 1..60_000,
       do: {:ok, min(left, max)}

  defp timeout(_, _), do: {:error, Error.new(:deadline_exceeded)}
end
