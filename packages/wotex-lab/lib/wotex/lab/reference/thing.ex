# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Runtime.Transport) do
  defmodule Wotex.Lab.Reference.Thing do
    @moduledoc """
    A simulated Thing host: canonical simulated state plus an explicit
    `Wotex.Runtime.ExposedThing` dispatch boundary.

    The host admits every request before any handler runs: the selected Form must
    declare the operation for its affordance (TD 1.1 defaults included), the
    credential must satisfy the Form's security definitions, and write and Action
    inputs must fit their DataSchema bounds. Rejected requests leave the handler
    call counter unchanged. Subscribers receive raw frames and are monitored so a
    dead subscriber is dropped. `disconnect/1` simulates session loss.

    Options: `:td` (a validated `Wotex.ThingDescription`), `:state` (initial
    Property values), `:tokens` (`security name => expected credential`), `:actions`
    (`action name => fn input, state -> {:ok, payload, status, next_state} end`, the
    explicit simulated effect of an invocation; unmapped actions store their input
    under the action name), and an optional `:name`. Start it under an instance's
    `:things` role.
    """

    use GenServer

    alias Wotex.{Form, ThingDescription}
    alias Wotex.Lab.Error
    alias Wotex.Runtime.{Context, ExposedThing, Request, Result}

    @type frame :: {:sample, String.t(), term(), map()} | {:event, String.t(), term(), map()}

    @doc false
    @spec child_spec(keyword()) :: Supervisor.child_spec()
    def child_spec(opts) do
      %{
        id: {__MODULE__, Keyword.get(opts, :id, :default)},
        start: {__MODULE__, :start_link, [opts]},
        restart: Keyword.get(opts, :restart, :transient),
        type: :worker
      }
    end

    @doc "Starts a simulated Thing host."
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
      case Keyword.get(opts, :name) do
        nil -> GenServer.start_link(__MODULE__, opts)
        name -> GenServer.start_link(__MODULE__, opts, name: name)
      end
    end

    @doc "Executes one runtime request against the host after admission."
    @spec request(pid(), Request.t(), term()) :: {:ok, Result.t()} | {:error, Error.t()}
    def request(host, %Request{} = request, credential),
      do: GenServer.call(host, {:request, request, credential})

    @doc "Registers a subscription owner for the request's affordance."
    @spec subscribe(pid(), Request.t(), pid(), term()) :: {:ok, reference()} | {:error, Error.t()}
    def subscribe(host, %Request{} = request, owner, credential),
      do: GenServer.call(host, {:subscribe, request, owner, credential})

    @doc "Removes a subscription."
    @spec unsubscribe(pid(), reference()) :: :ok | {:error, Error.t()}
    def unsubscribe(host, reference), do: GenServer.call(host, {:unsubscribe, reference})

    @doc "Records a new Property sample and delivers it to observers."
    @spec emit(pid(), String.t(), term(), map()) :: :ok
    def emit(host, name, value, meta \\ %{}), do: GenServer.call(host, {:emit, name, value, meta})

    @doc "Raises an Event and delivers it to subscribers."
    @spec raise_event(pid(), String.t(), term(), map()) :: :ok
    def raise_event(host, name, payload, meta \\ %{}),
      do: GenServer.call(host, {:event, name, payload, meta})

    @doc "Sends a keep-alive frame to every subscriber."
    @spec keepalive(pid()) :: :ok
    def keepalive(host), do: GenServer.call(host, :keepalive)

    @doc "Simulates session loss: every subscriber is told and dropped."
    @spec disconnect(pid()) :: :ok
    def disconnect(host), do: GenServer.call(host, :disconnect)

    @doc "Returns admission counters and the current simulated state."
    @spec stats(pid()) :: map()
    def stats(host), do: GenServer.call(host, :stats)

    @impl GenServer
    def init(opts) do
      td = Keyword.fetch!(opts, :td)

      case ExposedThing.new(td, handlers(td, Keyword.get(opts, :actions, %{}))) do
        {:ok, exposed} ->
          {:ok,
           %{
             exposed: exposed,
             document: ThingDescription.to_map(td),
             state: Keyword.get(opts, :state, %{}),
             tokens: Keyword.get(opts, :tokens, %{}),
             subscriptions: %{},
             handler_calls: 0,
             rejected: 0
           }}

        {:error, _reason} ->
          {:stop, :invalid_thing_description}
      end
    end

    @impl GenServer
    def handle_call({:request, %Request{} = request, credential}, _from, state) do
      with :ok <- admit_route(state.document, request),
           :ok <- admit_credential(state, request, credential),
           :ok <- admit_input(state.document, request) do
        dispatch(request, state)
      else
        {:error, error} -> {:reply, {:error, error}, %{state | rejected: state.rejected + 1}}
      end
    end

    def handle_call({:subscribe, %Request{} = request, owner, credential}, _from, state) do
      with :ok <- admit_route(state.document, request),
           :ok <- admit_credential(state, request, credential) do
        reference = make_ref()
        monitor = Process.monitor(owner)

        subscription = %{
          owner: owner,
          monitor: monitor,
          affordance_type: request.affordance_type,
          affordance_name: request.affordance_name,
          operation: request.operation
        }

        {:reply, {:ok, reference}, put_in(state, [:subscriptions, reference], subscription)}
      else
        {:error, error} -> {:reply, {:error, error}, %{state | rejected: state.rejected + 1}}
      end
    end

    def handle_call({:unsubscribe, reference}, _from, state) do
      case Map.pop(state.subscriptions, reference) do
        {nil, _subscriptions} ->
          {:reply, {:error, Error.new(:unknown_subscription, :host, "subscription is unknown")},
           state}

        {subscription, subscriptions} ->
          Process.demonitor(subscription.monitor, [:flush])
          {:reply, :ok, %{state | subscriptions: subscriptions}}
      end
    end

    def handle_call({:emit, name, value, meta}, _from, state) do
      state = put_in(state, [:state, name], value)
      broadcast(state, :property, name, {:sample, name, value, meta})
      {:reply, :ok, state}
    end

    def handle_call({:event, name, payload, meta}, _from, state) do
      broadcast(state, :event, name, {:event, name, payload, meta})
      {:reply, :ok, state}
    end

    def handle_call(:keepalive, _from, state) do
      Enum.each(state.subscriptions, fn {_reference, subscription} ->
        send(subscription.owner, {:wotex_transport_frame, :keepalive})
      end)

      {:reply, :ok, state}
    end

    def handle_call(:disconnect, _from, state) do
      Enum.each(state.subscriptions, fn {_reference, subscription} ->
        Process.demonitor(subscription.monitor, [:flush])
        send(subscription.owner, {:wotex_transport_status, :session_lost})
      end)

      {:reply, :ok, %{state | subscriptions: %{}}}
    end

    def handle_call(:stats, _from, state) do
      {:reply,
       %{
         handler_calls: state.handler_calls,
         rejected: state.rejected,
         subscriptions: map_size(state.subscriptions),
         state: state.state
       }, state}
    end

    @impl GenServer
    def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
      subscriptions =
        state.subscriptions
        |> Enum.reject(fn {_reference, subscription} -> subscription.monitor == monitor end)
        |> Map.new()

      {:noreply, %{state | subscriptions: subscriptions}}
    end

    def handle_info(_message, state), do: {:noreply, state}

    defp dispatch(%Request{} = request, state) do
      context = Context.new!(request_id: request.request_id, deadline: request.deadline)
      input = {request.input, state.state}

      case ExposedThing.dispatch(
             state.exposed,
             request.operation,
             request.affordance_name,
             input,
             context
           ) do
        {:ok, payload, status, next_state} ->
          {:ok, result} =
            Result.new(request.request_id, request.operation, payload,
              status: status,
              metadata: %{binding: :loopback}
            )

          {:reply, {:ok, result},
           %{state | state: next_state, handler_calls: state.handler_calls + 1}}

        {:error, error} ->
          {:reply, {:error, host_error(error)}, %{state | rejected: state.rejected + 1}}
      end
    end

    defp handlers(td, effects) do
      document = ThingDescription.to_map(td)

      properties =
        document
        |> Map.get("properties", %{})
        |> Enum.flat_map(fn {name, _affordance} ->
          [
            {{:readproperty, name},
             fn {_input, state}, _context -> {:ok, Map.get(state, name), :ok, state} end},
            {{:writeproperty, name},
             fn {input, state}, _context -> {:ok, nil, :ok, Map.put(state, name, input)} end}
          ]
        end)

      actions =
        document
        |> Map.get("actions", %{})
        |> Enum.map(fn {name, _affordance} ->
          {{:invokeaction, name}, action_handler(name, Map.get(effects, name))}
        end)

      Map.new(properties ++ actions)
    end

    defp action_handler(name, nil) do
      fn {input, state}, _context ->
        {:ok, %{"accepted" => true, "input" => input}, :accepted, Map.put(state, name, input)}
      end
    end

    defp action_handler(_name, effect) when is_function(effect, 2) do
      fn {input, state}, _context -> effect.(input, state) end
    end

    defp admit_route(_document, %Request{affordance_type: :thing}) do
      {:error, Error.new(:unsupported_operation, :host, "Thing-level operations are not simulated")}
    end

    defp admit_route(document, %Request{} = request) do
      container =
        %{property: "properties", action: "actions", event: "events"}[request.affordance_type]

      affordance = get_in(document, [container, request.affordance_name]) || %{}

      declared? =
        affordance
        |> Map.get("forms", [])
        |> Enum.any?(fn form_map ->
          case Form.new(form_map, for: request.affordance_type) do
            {:ok, form} ->
              Atom.to_string(request.operation) in Form.operations(form,
                for: request.affordance_type,
                read_only: Map.get(affordance, "readOnly") == true,
                write_only: Map.get(affordance, "writeOnly") == true
              )

            {:error, _error} ->
              false
          end
        end)

      if declared? do
        :ok
      else
        {:error,
         Error.new(
           :operation_not_declared,
           :host,
           "no Form declares the operation for this affordance",
           class: :permanent
         )}
      end
    end

    defp admit_credential(state, %Request{} = request, credential) do
      definitions = Map.get(state.document, "securityDefinitions", %{})

      state.document
      |> security_names(request)
      |> Enum.reduce_while(:ok, fn name, :ok ->
        if satisfied?(Map.get(definitions, name), Map.get(state.tokens, name), credential, name),
          do: {:cont, :ok},
          else: {:halt, {:error, unauthorized()}}
      end)
    end

    defp satisfied?(%{"scheme" => "nosec"}, _expected, _credential, _name), do: true
    defp satisfied?(_definition, nil, _credential, _name), do: false

    defp satisfied?(_definition, expected, credential, name) when is_map(credential),
      do: Map.get(credential, name) == expected

    defp satisfied?(_definition, _expected, _credential, _name), do: false

    defp unauthorized do
      Error.new(:unauthorized, :host, "credential does not satisfy the selected security",
        class: :permanent
      )
    end

    defp security_names(document, %Request{form: form}) do
      form
      |> Form.to_map()
      |> Map.get("security", Map.get(document, "security", []))
      |> List.wrap()
    end

    defp admit_input(document, %Request{operation: :writeproperty} = request) do
      schema = get_in(document, ["properties", request.affordance_name]) || %{}
      check_number(schema, request.input)
    end

    defp admit_input(document, %Request{operation: :invokeaction} = request) do
      schema = get_in(document, ["actions", request.affordance_name, "input"]) || %{}
      check_number(schema, request.input)
    end

    defp admit_input(_document, _request), do: :ok

    defp check_number(%{"type" => "number"} = schema, value) when is_number(value) do
      minimum = Map.get(schema, "minimum")
      maximum = Map.get(schema, "maximum")

      if (is_nil(minimum) or value >= minimum) and (is_nil(maximum) or value <= maximum) do
        :ok
      else
        {:error,
         Error.new(:input_out_of_range, :host, "input violates the DataSchema bounds",
           class: :permanent
         )}
      end
    end

    defp check_number(%{"type" => "number"}, _value) do
      {:error, Error.new(:invalid_input_type, :host, "input must be a number", class: :permanent)}
    end

    defp check_number(_schema, _value), do: :ok

    defp broadcast(state, type, name, frame) do
      Enum.each(state.subscriptions, fn {_reference, subscription} ->
        if subscription.affordance_type == type and subscription.affordance_name == name do
          send(subscription.owner, {:wotex_transport_frame, frame})
        end
      end)
    end

    defp host_error(%Wotex.Runtime.Error{code: code}) do
      Error.new(code, :host, "ExposedThing refused the request", class: :permanent)
    end
  end
end
