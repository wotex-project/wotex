defmodule Wotex.BACnet.Transport do
  @moduledoc "Scoped Wotex Runtime execution over an explicit client and exact target identity."
  @behaviour Wotex.Runtime.Transport
  alias Wotex.BACnet
  alias Wotex.BACnet.{COVOptions, Error, Mapping, RuntimeFrame, RuntimeRelay, Value}
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{credential: nil}, config)
      when is_list(config) and request.operation in [:readproperty, :writeproperty] do
    with true <- valid_options?(config),
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, timeout} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)) do
      deadline = System.monotonic_time(:millisecond) + timeout

      options =
        config
        |> Keyword.drop([:target, :cov])
        |> Keyword.put(:timeout, timeout)

      BACnet.with_connection(options, fn session ->
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
  def subscribe(
        %Request{operation: :observeproperty} = request,
        owner,
        %ExecutionContext{credential: nil},
        config
      )
      when is_pid(owner) and is_list(config) do
    with true <- valid_options?(config) and Process.alive?(owner),
         {:ok, mapping} <-
           Mapping.command(request.form, :observeproperty, nil, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, timeout} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)),
         {:ok, cov} <- COVOptions.request(mapping.message, Keyword.get(config, :cov, %{}), owner) do
      RuntimeRelay.open(%{
        owner: owner,
        request: cov,
        client_options: Keyword.drop(config, [:target, :cov]),
        deadline: System.monotonic_time(:millisecond) + timeout
      })
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_context)}
    end
  end

  def subscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, _, _, _), do: RuntimeRelay.close(handle)

  @impl Wotex.Runtime.Transport
  def decode_frame(
        {:value, value, metadata},
        %Request{operation: :observeproperty} = request,
        config
      )
      when is_list(config) do
    with true <- valid_options?(config),
         {:ok, mapping} <-
           Mapping.command(request.form, :observeproperty, nil, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, cov} <- COVOptions.request(mapping.message, Keyword.get(config, :cov, %{}), self()),
         :ok <- RuntimeFrame.validate(value, metadata, cov, Keyword.get(config, :destination)) do
      RuntimeFrame.project(value, metadata)
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_runtime_frame)}
    end
  end

  def decode_frame({:error, %Error{}} = error, _, _), do: error
  def decode_frame(_, _, _), do: :ignore

  defp valid_options?(config) do
    Keyword.keyword?(config) and
      length(Keyword.keys(config)) == length(Enum.uniq(Keyword.keys(config)))
  end

  defp execute(session, message, request, remaining) when remaining > 0 do
    with {:ok, value} <- BACnet.send(%{session | timeout: remaining}, message) do
      {payload, metadata} = Value.result(value)
      Result.new(request.request_id, request.operation, payload, metadata: metadata)
    end
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
