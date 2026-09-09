defmodule Wotex.BACnet.Transport do
  @moduledoc """
  Executes Wotex Runtime requests through a scoped BACnet client session.

  `Wotex.BACnet.Transport` implements the Runtime transport boundary for the
  package's supported Property operations. It validates the execution context,
  maps the selected Form through `Wotex.BACnet.Mapping`, opens the configured
  client, validates the native reply, and closes the exact session. A single
  deadline covers mapping, setup, exchange, conversion, and successful cleanup.
  Property observations use a relay that monitors the Runtime owner and owns
  the native COV session, handle, reports, and cancellation lifecycle.

  ## Runtime boundary

  The transport requires an exact target identity and rejects credentials in
  the execution context because this profile has no credential transport
  contract. Runtime selection does not grant permission to contact a peer, and
  a successful request does not establish canonical Property truth. The
  consumer owns authorization, routing, deadlines, supervision, and any policy
  for interpreting returned BACnet metadata.
  """
  @behaviour Wotex.Runtime.Transport
  alias Wotex.BACnet.{COVOptions, Error, Mapping, RuntimeExchange, RuntimeFrame, RuntimeRelay}
  alias Wotex.Runtime.{Context, ExecutionContext, Request}

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{credential: nil}, config)
      when is_list(config) and request.operation in [:readproperty, :writeproperty] do
    with true <- valid_options?(config),
         {:ok, deadline} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)),
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target do
      RuntimeExchange.run(Keyword.drop(config, [:target, :cov]), mapping.message, request, deadline)
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
         :ok <- receive_policy(config),
         {:ok, deadline} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)),
         {:ok, mapping} <-
           Mapping.command(request.form, :observeproperty, nil, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, cov} <- COVOptions.request(mapping.message, Keyword.get(config, :cov, %{}), owner) do
      RuntimeRelay.open(%{
        owner: owner,
        request: cov,
        client_options: Keyword.drop(config, [:target, :cov]),
        deadline: deadline
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

  defp receive_policy(config) do
    if Keyword.get(config, :client) == Wotex.BACnet.BACstack and
         Keyword.get(config, :receive_policy) != :wotex_bounded,
       do: {:error, Error.new(:unbounded_receive_policy)},
       else: :ok
  end

  defp budget(deadline, max) when is_integer(max) and max in 1..60_000 do
    monotonic = System.monotonic_time(:millisecond)

    now =
      if is_struct(deadline, DateTime),
        do: DateTime.utc_now(),
        else: monotonic

    case Context.remaining_ms(deadline, now) do
      :infinity -> {:ok, monotonic + max}
      left when is_integer(left) and left > 0 -> {:ok, monotonic + min(left, max)}
      _ -> {:error, Error.new(:deadline_exceeded)}
    end
  end

  defp budget(_, _), do: {:error, Error.new(:invalid_timeout)}
end
