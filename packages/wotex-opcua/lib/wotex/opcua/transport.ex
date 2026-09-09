defmodule Wotex.OPCUA.Transport do
  @moduledoc """
  Executes Wotex Runtime requests through a scoped OPC UA client session.

  The transport validates the Runtime request and execution context, maps the
  selected Form through `Wotex.OPCUA.Mapping`, opens the configured client,
  performs one read or write, normalizes the result, and closes the exact
  session. Subscription callbacks return explicit unsupported errors because
  the current transport does not maintain OPC UA subscriptions.

  ## Runtime boundary

  Credentials are rejected at this boundary because the client configuration
  owns the secure-channel material. Runtime Form selection is not
  authorization, and successful service completion does not establish canonical
  Property truth or a physical effect. The consumer owns endpoint policy,
  credential provisioning, deadlines, supervision, data-model validation, and
  interpretation of returned status metadata.
  """
  @behaviour Wotex.Runtime.Transport
  alias Wotex.OPCUA
  alias Wotex.OPCUA.{Error, Mapping, Value}
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

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

      OPCUA.with_connection(options, fn session ->
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
    with {:ok, value} <- OPCUA.send(%{session | timeout: remaining}, message),
         {:ok, payload, metadata} <- Value.result(value),
         do: Result.new(request.request_id, request.operation, payload, metadata: metadata)
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
