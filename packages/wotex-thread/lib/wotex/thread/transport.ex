defmodule Wotex.Thread.Transport do
  @moduledoc "Scoped Wotex Runtime execution over an explicit client and exact target identity."
  @behaviour Wotex.Runtime.Transport
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}
  alias Wotex.Thread
  alias Wotex.Thread.{Error, Mapping}

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{credential: nil}, config)
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

      Thread.with_connection(options, fn session ->
        remaining = deadline - System.monotonic_time(:millisecond)
        execute(session, mapping.message, request, remaining)
      end)
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:target_mismatch)}
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}
  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  defp execute(session, message, request, remaining) when remaining > 0 do
    with {:ok, value} <- Thread.send(%{session | timeout: remaining}, message),
         do: Result.new(request.request_id, request.operation, value)
  end

  defp execute(_, _, _, _), do: {:error, Error.new(:deadline_exceeded)}

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
