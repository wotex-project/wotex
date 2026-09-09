defmodule Wotex.BLE.Transport do
  @moduledoc "Scoped Wotex Runtime execution over an explicit client and exact target identity."
  @behaviour Wotex.Runtime.Transport
  alias Wotex.BLE
  alias Wotex.BLE.{Error, Mapping, Value}
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

  @impl Wotex.Runtime.Transport
  def request(
        %Request{affordance_type: :property, operation: operation} = request,
        execution,
        config
      )
      when operation in [:readproperty, :writeproperty] do
    with {:ok, prepared} <- prepare(request, execution, config) do
      BLE.with_connection(prepared.options, fn session ->
        execute(session, prepared, request)
      end)
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @doc false
  @spec prepare(Request.t(), ExecutionContext.t(), term()) :: {:ok, map()} | {:error, Error.t()}
  def prepare(%Request{} = request, %ExecutionContext{credential: nil, context: context}, config) do
    with :ok <- request_context(request, context),
         :ok <- configuration(config),
         :ok <- profile(request),
         {:ok, timeout} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)),
         deadline = System.monotonic_time(:millisecond) + timeout,
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, remaining} <- remaining(deadline) do
      options =
        config
        |> Keyword.delete(:target)
        |> Keyword.put(:timeout, remaining)

      {:ok, %{mapping: mapping, options: options, deadline: deadline}}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:target_mismatch)}
    end
  end

  def prepare(_, %ExecutionContext{credential: credential}, _) when credential != nil,
    do: {:error, Error.new(:unsupported_security)}

  def prepare(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  defp request_context(request, %Context{} = context) do
    with {:ok, _} <- Context.new(request_id: request.request_id, deadline: request.deadline),
         true <- request.request_id == Context.request_id(context),
         true <- request.deadline == Context.deadline(context),
         do: :ok,
         else: (_ -> {:error, Error.new(:invalid_transport_context)})
  end

  defp request_context(_, _), do: {:error, Error.new(:invalid_transport_context)}

  defp configuration(config) do
    cond do
      not Keyword.keyword?(config) ->
        {:error, Error.new(:invalid_options)}

      length(Keyword.keys(config)) != length(Enum.uniq(Keyword.keys(config))) ->
        {:error, Error.new(:invalid_options)}

      Keyword.has_key?(config, :security_mode) ->
        {:error, Error.new(:unsupported_security)}

      true ->
        :ok
    end
  end

  defp profile(%Request{profile: profile, operation: operation}) do
    if profile == BLE.profile() and operation in [:readproperty, :writeproperty],
      do: :ok,
      else: {:error, Error.new(:unsupported_profile)}
  end

  defp execute(session, prepared, request) do
    with {:ok, remaining} <- remaining(prepared.deadline),
         session = %{session | timeout: remaining},
         {:ok, value} <- BLE.send(session, prepared.mapping.message),
         {:ok, payload} <- decode(value, prepared.mapping),
         :ok <- completion(prepared.deadline, request.operation),
         do: Result.new(request.request_id, request.operation, payload)
  end

  defp decode(:written, %{message: %{type: :write}}), do: {:ok, :written}

  defp decode(_, %{message: %{type: :write}}),
    do: {:error, Error.unknown_effect(Error.new(:invalid_transport_return))}

  defp decode(value, mapping) do
    case Value.decode(value, mapping.value_type, byte_order: mapping.byte_order) do
      {:ok, _} = result -> result
      {:error, _} -> {:error, Error.new(:invalid_response)}
    end
  end

  defp completion(deadline, :writeproperty) do
    case remaining(deadline) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, Error.unknown_effect(error)}
    end
  end

  defp completion(deadline, _) do
    case remaining(deadline) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp remaining(deadline) do
    left = deadline - now()
    if left > 0, do: {:ok, left}, else: {:error, Error.new(:deadline_exceeded)}
  end

  defp budget(deadline, max) when is_integer(max) and max in 1..60_000 do
    clock = if is_struct(deadline, DateTime), do: DateTime.utc_now(), else: now()

    case Context.remaining_ms(deadline, clock) do
      :infinity -> {:ok, max}
      left when is_integer(left) and left > 0 -> {:ok, min(left, max)}
      _ -> {:error, Error.new(:deadline_exceeded)}
    end
  end

  defp budget(_, _), do: {:error, Error.new(:invalid_timeout)}
  defp now, do: System.monotonic_time(:millisecond)
end
