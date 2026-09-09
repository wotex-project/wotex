defmodule Wotex.BLE.Transport do
  @moduledoc """
  Executes Wotex Runtime requests and subscriptions through explicit BLE sessions.

  One-shot requests validate the Runtime request/context identity, profile,
  deadline and exact configured target, then map the Form, open the client,
  perform one read or acknowledged write and close the session. Native value
  codecs decode reads; write completion is `:written`, not a readback value.

  The `:ble_gatt` profile requires the first-party persistent BlueZ backend.
  Property observation and Event subscriptions use `Wotex.BLE.RuntimeRelay`,
  which owns a session until cancellation or failure and forwards only
  validated value-change frames to the public Runtime owner. Cancellation
  closes the original handle; later request configuration cannot retarget it.

  Forms must omit contentType. Explicit Runtime credentials and security-mode
  configuration are rejected because this binding defines no credential
  transport. Peer selection, pairing trust and physical interpretation remain
  consumer policy. BlueZ value-change metadata does not distinguish ATT
  notifications from read-induced Value updates or certify security strength.
  """
  @behaviour Wotex.Runtime.Transport
  alias Wotex.BLE
  alias Wotex.BLE.{BlueZ, Error, Mapping, RuntimeFrame, RuntimeRelay, Value}
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
  def subscribe(
        %Request{affordance_type: type, operation: operation} = request,
        owner,
        execution,
        config
      )
      when is_pid(owner) and
             ((type == :property and operation == :observeproperty) or
                (type == :event and operation == :subscribeevent)) do
    with {:ok, prepared} <- prepare(request, execution, config),
         do: RuntimeRelay.open(prepared, owner, prepared.limit)
  end

  def subscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(%RuntimeRelay{} = handle, _, _, _), do: RuntimeRelay.close(handle)
  def unsubscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @impl Wotex.Runtime.Transport
  def decode_frame(frame, %Request{} = request, _) do
    with {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         do: RuntimeFrame.decode(frame, mapping)
  end

  def decode_frame(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @doc false
  @spec prepare(Request.t(), ExecutionContext.t(), term()) :: {:ok, map()} | {:error, Error.t()}
  def prepare(%Request{} = request, %ExecutionContext{credential: nil, context: context}, config) do
    with :ok <- request_context(request, context),
         :ok <- configuration(config),
         :ok <- profile(request, config),
         {:ok, limit} <- queue_limit(config),
         {:ok, timeout} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)),
         deadline = System.monotonic_time(:millisecond) + timeout,
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, remaining} <- remaining(deadline) do
      options =
        config
        |> Keyword.drop([:target, :max_queue_length])
        |> Keyword.put(:timeout, remaining)

      {:ok, %{mapping: mapping, options: options, deadline: deadline, limit: limit}}
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

  defp profile(%Request{profile: profile, operation: operation}, config) do
    {:ok, gatt} = BLE.profile(:gatt)

    cond do
      profile == BLE.profile() and operation in [:readproperty, :writeproperty] ->
        :ok

      profile == gatt and
          operation in [:readproperty, :writeproperty, :observeproperty, :subscribeevent] ->
        streaming_options(config)

      true ->
        {:error, Error.new(:unsupported_profile)}
    end
  end

  defp streaming_options(config) do
    if Keyword.get(config, :client) == BlueZ and Keyword.get(config, :lifecycle) == :persistent and
         not Keyword.has_key?(config, :owner),
       do: :ok,
       else: {:error, Error.new(:unsupported_profile)}
  end

  defp queue_limit(config) do
    limit = Keyword.get(config, :max_queue_length, 1000)

    if is_integer(limit) and limit in 1..10_000,
      do: {:ok, limit},
      else: {:error, Error.new(:invalid_options)}
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
