defmodule Wotex.Runtime.Subscription do
  @moduledoc """
  Explicit caller-supervised observation or Event subscription.

  The process exists only when the caller starts a returned child specification.
  On initialization it resolves credentials, opens the selected transport
  subscription, and holds only the transport handle. Values arrive as
  `{:wotex_transport, payload}` and are forwarded with the consumer-selected
  subscription id.

  Use the child-spec functions on `Wotex.Runtime.ConsumedThing` to construct
  subscriptions. The consumer owns the parent supervisor, child identity,
  restart policy, shutdown budget, receiver, and failure handling.
  """

  use GenServer

  alias Wotex.Runtime.{Context, Error, ExecutionContext}

  @doc false
  @spec start_link(%{required(:name) => GenServer.name() | nil, optional(atom()) => term()}) ::
          GenServer.on_start()
  def start_link(%{name: nil} = init), do: GenServer.start_link(__MODULE__, init)
  def start_link(%{name: name} = init), do: GenServer.start_link(__MODULE__, init, name: name)

  @doc "Stops a subscription after requesting protocol unsubscription."
  @spec stop(GenServer.server(), timeout()) :: :ok | {:error, Error.t()}
  def stop(server, timeout \\ 5_000), do: GenServer.call(server, :stop, timeout)

  @impl GenServer
  def init(init) do
    case subscribe(init) do
      {:ok, handle} ->
        {:ok,
         init
         |> Map.put(:handle, handle)
         |> Map.put(:closed?, false)}

      {:error, error} ->
        {:stop, error}
    end
  end

  @impl GenServer
  def handle_call(:stop, _from, state) do
    result = unsubscribe(state)
    {:stop, :normal, result, %{state | closed?: true}}
  end

  @impl GenServer
  def handle_info({:wotex_transport, payload}, state) do
    send(state.receiver, {:wotex_runtime, state.id, payload})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{closed?: true}), do: :ok
  def terminate(_reason, state), do: unsubscribe(state)

  defp subscribe(init) do
    with {:ok, execution_context} <-
           resolve_credentials(
             init.credentials,
             init.start_security,
             init.start_request.form,
             init.context
           ),
         {module, config} = init.transport,
         {:ok, handle} <-
           normalize_subscribe(
             module.subscribe(init.start_request, self(), execution_context, config),
             init.start_request
           ) do
      {:ok, handle}
    end
  end

  defp unsubscribe(state) do
    with {:ok, execution_context} <-
           resolve_credentials(
             state.credentials,
             state.stop_security,
             state.stop_request.form,
             state.context
           ),
         {module, config} = state.transport do
      normalize_unsubscribe(
        module.unsubscribe(state.handle, state.stop_request, execution_context, config),
        state.stop_request
      )
    end
  end

  defp resolve_credentials({module, config}, security, form, %Context{} = context) do
    case module.resolve(security, form, context, config) do
      {:ok, credential} ->
        {:ok, ExecutionContext.new(context, credential)}

      {:error, _external} ->
        {:error,
         Error.new(:credential_resolution_failed, :credentials, "credential resolution failed", %{
           request_id: Context.request_id(context)
         })}

      _invalid ->
        {:error,
         Error.new(
           :invalid_credentials_return,
           :credentials,
           "credential port returned an invalid value",
           %{
             request_id: Context.request_id(context)
           }
         )}
    end
  end

  defp normalize_subscribe({:ok, handle}, _request), do: {:ok, handle}

  defp normalize_subscribe({:error, _external}, request) do
    {:error,
     Error.new(:transport_subscribe_failed, :subscription, "transport subscription failed", %{
       request_id: request.request_id,
       operation: request.operation
     })}
  end

  defp normalize_subscribe(_invalid, request) do
    {:error,
     Error.new(
       :invalid_transport_return,
       :subscription,
       "transport returned an invalid subscription value",
       %{
         request_id: request.request_id,
         operation: request.operation
       }
     )}
  end

  defp normalize_unsubscribe(:ok, _request), do: :ok

  defp normalize_unsubscribe({:error, _external}, request) do
    {:error,
     Error.new(:transport_unsubscribe_failed, :subscription, "transport unsubscription failed", %{
       request_id: request.request_id,
       operation: request.operation
     })}
  end

  defp normalize_unsubscribe(_invalid, request) do
    {:error,
     Error.new(
       :invalid_transport_return,
       :subscription,
       "transport returned an invalid unsubscription value",
       %{
         request_id: request.request_id,
         operation: request.operation
       }
     )}
  end
end
