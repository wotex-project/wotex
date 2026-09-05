defmodule Wotex.Runtime.ConsumedThing do
  @moduledoc """
  An immutable plan for consuming a Thing through caller-supplied ports.

  Construction validates the Thing Description, requires at least one unique
  binding profile, requires a transport implementation for every profile, and
  checks the credential-provider port. No connection or credential lookup
  happens during construction.

  Property reads/writes, Action invocation/query/cancellation, and Thing-level
  aggregate requests execute in the caller and return typed protocol results.
  Observation and Event APIs return child specifications and start no process
  themselves. The consumer chooses child ids, names, receivers, restart
  strategies, shutdown budgets, and supervision placement.

  A ConsumedThing is an interaction plan. It does not own the described Thing,
  authorize requests, persist observations, or assert that transport success
  represents canonical state or a completed physical effect.
  """

  alias Wotex.ThingDescription

  alias Wotex.Runtime.{
    BindingProfile,
    Context,
    Error,
    ExecutionContext,
    FormSelector,
    Request,
    Result,
    Selection,
    Subscription
  }

  @type t :: %__MODULE__{
          td: ThingDescription.t(),
          profiles: [BindingProfile.t()],
          transports: map(),
          credentials: {module(), term()}
        }

  @enforce_keys [:td, :profiles, :transports, :credentials]
  defstruct [:td, :profiles, :transports, :credentials]

  @doc "Builds a ConsumedThing from a validated TD and explicit runtime ports."
  @spec new(ThingDescription.t(), keyword()) :: {:ok, t()} | {:error, Error.t() | [Wotex.Error.t()]}
  def new(%ThingDescription{} = td, opts) when is_list(opts) do
    profiles = Keyword.get(opts, :profiles)
    transports = Keyword.get(opts, :transports)
    credentials = Keyword.get(opts, :credentials)

    with {:ok, validated} <- ThingDescription.validate(td),
         :ok <- validate_profiles(profiles),
         :ok <- validate_transports(profiles, transports),
         :ok <- validate_credentials(credentials) do
      {:ok,
       %__MODULE__{
         td: validated,
         profiles: profiles,
         transports: transports,
         credentials: credentials
       }}
    end
  end

  def new(_td, _opts) do
    {:error,
     Error.new(
       :invalid_consumed_thing,
       :construction,
       "a Thing Description and keyword options are required"
     )}
  end

  @doc "Executes `readproperty` in the caller process."
  @spec read_property(t(), String.t(), Context.t()) :: {:ok, Result.t()} | {:error, Error.t()}
  def read_property(consumed, name, context),
    do:
      execute(
        consumed,
        %{type: :property, name: name, operation: :readproperty, input: nil},
        context
      )

  @doc "Executes `writeproperty` in the caller process."
  @spec write_property(t(), String.t(), term(), Context.t()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def write_property(consumed, name, input, context),
    do:
      execute(
        consumed,
        %{type: :property, name: name, operation: :writeproperty, input: input},
        context
      )

  @doc "Executes `invokeaction` in the caller process."
  @spec invoke_action(t(), String.t(), term(), Context.t()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def invoke_action(consumed, name, input, context),
    do:
      execute(
        consumed,
        %{type: :action, name: name, operation: :invokeaction, input: input},
        context
      )

  @doc "Executes `queryaction` in the caller process."
  @spec query_action(t(), String.t(), term(), Context.t()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def query_action(consumed, name, invocation, context),
    do:
      execute(
        consumed,
        %{type: :action, name: name, operation: :queryaction, input: invocation},
        context
      )

  @doc "Executes `cancelaction` in the caller process."
  @spec cancel_action(t(), String.t(), term(), Context.t()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def cancel_action(consumed, name, invocation, context),
    do:
      execute(
        consumed,
        %{type: :action, name: name, operation: :cancelaction, input: invocation},
        context
      )

  @doc "Executes `readallproperties` in the caller process."
  @spec read_all_properties(t(), Context.t()) :: {:ok, Result.t()} | {:error, Error.t()}
  def read_all_properties(consumed, context),
    do:
      execute(
        consumed,
        %{type: :thing, name: nil, operation: :readallproperties, input: nil},
        context
      )

  @doc "Executes `readmultipleproperties` for an ordered list of Property names."
  @spec read_multiple_properties(t(), [String.t()], Context.t()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def read_multiple_properties(consumed, names, context) do
    if valid_property_names?(names) do
      execute(
        consumed,
        %{type: :thing, name: nil, operation: :readmultipleproperties, input: names},
        context
      )
    else
      {:error,
       Error.new(
         :invalid_property_names,
         :construction,
         "readmultipleproperties requires non-empty Property names"
       )}
    end
  end

  @doc "Executes `writeallproperties` with a Property-name map."
  @spec write_all_properties(t(), map(), Context.t()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def write_all_properties(consumed, values, context),
    do: write_properties(consumed, :writeallproperties, values, context)

  @doc "Executes `writemultipleproperties` with a Property-name map."
  @spec write_multiple_properties(t(), map(), Context.t()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def write_multiple_properties(consumed, values, context),
    do: write_properties(consumed, :writemultipleproperties, values, context)

  @doc "Executes `queryallactions` in the caller process."
  @spec query_all_actions(t(), Context.t()) :: {:ok, Result.t()} | {:error, Error.t()}
  def query_all_actions(consumed, context),
    do:
      execute(
        consumed,
        %{type: :thing, name: nil, operation: :queryallactions, input: nil},
        context
      )

  @doc "Returns a caller-supervised Property observation child specification."
  @spec observation_child_spec(t(), String.t(), Context.t(), keyword()) ::
          {:ok, Supervisor.child_spec()} | {:error, Error.t()}
  def observation_child_spec(consumed, name, context, opts),
    do:
      subscription_child_spec(
        consumed,
        %{type: :property, name: name, start: :observeproperty, stop: :unobserveproperty},
        context,
        opts
      )

  @doc "Returns a caller-supervised Event subscription child specification."
  @spec event_subscription_child_spec(t(), String.t(), Context.t(), keyword()) ::
          {:ok, Supervisor.child_spec()} | {:error, Error.t()}
  def event_subscription_child_spec(consumed, name, context, opts),
    do:
      subscription_child_spec(
        consumed,
        %{type: :event, name: name, start: :subscribeevent, stop: :unsubscribeevent},
        context,
        opts
      )

  @doc "Returns a caller-supervised aggregate Property observation child specification."
  @spec all_properties_observation_child_spec(t(), Context.t(), keyword()) ::
          {:ok, Supervisor.child_spec()} | {:error, Error.t()}
  def all_properties_observation_child_spec(consumed, context, opts),
    do:
      subscription_child_spec(
        consumed,
        %{type: :thing, name: nil, start: :observeallproperties, stop: :unobserveallproperties},
        context,
        opts
      )

  @doc "Returns a caller-supervised aggregate Event subscription child specification."
  @spec all_events_subscription_child_spec(t(), Context.t(), keyword()) ::
          {:ok, Supervisor.child_spec()} | {:error, Error.t()}
  def all_events_subscription_child_spec(consumed, context, opts),
    do:
      subscription_child_spec(
        consumed,
        %{type: :thing, name: nil, start: :subscribeallevents, stop: :unsubscribeallevents},
        context,
        opts
      )

  @doc "Returns the immutable Thing Description."
  @spec thing_description(t()) :: ThingDescription.t()
  def thing_description(%__MODULE__{td: td}), do: td

  defp execute(%__MODULE__{} = consumed, interaction, %Context{} = context) do
    with {:ok, selection} <- select(consumed, interaction, consumed.profiles),
         {:ok, transport} <- transport_for(consumed, selection),
         request = Request.from_selection(selection, context, interaction.input),
         {:ok, execution_context} <- resolve_credentials(consumed, selection, context),
         {:ok, result} <- transport_request(transport, request, execution_context) do
      {:ok, result}
    end
  end

  defp execute(%__MODULE__{}, _interaction, _context) do
    {:error, Error.new(:invalid_context, :construction, "a Wotex Runtime Context is required")}
  end

  defp execute(_consumed, _interaction, _context) do
    {:error, Error.new(:invalid_consumed_thing, :construction, "a ConsumedThing is required")}
  end

  defp subscription_child_spec(
         %__MODULE__{} = consumed,
         interaction,
         %Context{} = context,
         opts
       )
       when is_list(opts) do
    with {:ok, id} <- required_option(opts, :id),
         {:ok, receiver} <- required_option(opts, :receiver),
         {:ok, start_selection} <-
           select(consumed, Map.put(interaction, :operation, interaction.start), consumed.profiles),
         {:ok, transport} <- transport_for(consumed, start_selection),
         {:ok, stop_selection} <-
           select(
             consumed,
             Map.put(interaction, :operation, interaction.stop),
             [start_selection.profile]
           ) do
      start_request = Request.from_selection(start_selection, context, Keyword.get(opts, :input))
      stop_request = Request.from_selection(stop_selection, context, Keyword.get(opts, :stop_input))

      init = %{
        id: id,
        receiver: receiver,
        name: Keyword.get(opts, :name),
        start_request: start_request,
        stop_request: stop_request,
        start_security: start_selection.security,
        stop_security: stop_selection.security,
        context: context,
        credentials: consumed.credentials,
        transport: transport
      }

      {:ok,
       %{
         id: id,
         start: {Subscription, :start_link, [init]},
         restart: Keyword.get(opts, :restart, :permanent),
         shutdown: Keyword.get(opts, :shutdown, 5_000),
         type: :worker
       }}
    end
  end

  defp subscription_child_spec(
         %__MODULE__{},
         _interaction,
         _context,
         _opts
       ) do
    {:error,
     Error.new(
       :invalid_subscription_options,
       :construction,
       "context and keyword options are required"
     )}
  end

  defp subscription_child_spec(
         _consumed,
         _interaction,
         _context,
         _opts
       ) do
    {:error, Error.new(:invalid_consumed_thing, :construction, "a ConsumedThing is required")}
  end

  defp required_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, nil} ->
        {:error,
         Error.new(
           :missing_subscription_option,
           :construction,
           "subscription option is required",
           %{
             option: key
           }
         )}

      {:ok, value} ->
        {:ok, value}

      :error ->
        {:error,
         Error.new(
           :missing_subscription_option,
           :construction,
           "subscription option is required",
           %{
             option: key
           }
         )}
    end
  end

  defp select(consumed, %{type: :thing, operation: operation}, profiles),
    do: FormSelector.select_thing(consumed.td, operation, profiles)

  defp select(consumed, interaction, profiles),
    do:
      FormSelector.select(
        consumed.td,
        interaction.type,
        interaction.name,
        interaction.operation,
        profiles
      )

  defp write_properties(consumed, operation, values, context) do
    if valid_property_map?(values) do
      execute(consumed, %{type: :thing, name: nil, operation: operation, input: values}, context)
    else
      {:error,
       Error.new(
         :invalid_property_map,
         :construction,
         "aggregate Property writes require a non-empty Property-name map"
       )}
    end
  end

  defp valid_property_names?(names) when is_list(names) and names != [],
    do: Enum.all?(names, &(is_binary(&1) and byte_size(String.trim(&1)) > 0))

  defp valid_property_names?(_names), do: false

  defp valid_property_map?(values) when is_map(values) and map_size(values) > 0,
    do: Enum.all?(Map.keys(values), &(is_binary(&1) and byte_size(String.trim(&1)) > 0))

  defp valid_property_map?(_values), do: false

  defp validate_profiles(profiles) when is_list(profiles) and profiles != [] do
    if Enum.all?(profiles, &match?(%BindingProfile{}, &1)) do
      ids = Enum.map(profiles, &BindingProfile.id/1)

      if length(ids) == MapSet.size(MapSet.new(ids)) do
        :ok
      else
        {:error, Error.new(:duplicate_profile_id, :construction, "profile ids must be unique")}
      end
    else
      {:error,
       Error.new(:invalid_profiles, :construction, "profiles must contain BindingProfile values")}
    end
  end

  defp validate_profiles(_profiles) do
    {:error, Error.new(:invalid_profiles, :construction, "at least one BindingProfile is required")}
  end

  defp validate_transports(profiles, transports) when is_map(transports) do
    missing =
      Enum.reject(profiles, fn profile ->
        case Map.get(transports, BindingProfile.id(profile)) do
          {module, _config} when is_atom(module) and not is_nil(module) ->
            transport_module?(module)

          _missing_or_invalid ->
            false
        end
      end)

    if missing == [] do
      :ok
    else
      {:error,
       Error.new(:missing_transport, :construction, "every profile must have a transport port", %{
         profile_ids: Enum.map(missing, &BindingProfile.id/1)
       })}
    end
  end

  defp validate_transports(_profiles, _transports) do
    {:error, Error.new(:invalid_transports, :construction, "transports must be a profile-id map")}
  end

  defp validate_credentials({module, _config}) when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :resolve, 4) do
      :ok
    else
      {:error,
       Error.new(
         :invalid_credentials_port,
         :construction,
         "credentials module must implement resolve/4"
       )}
    end
  end

  defp validate_credentials(_credentials) do
    {:error,
     Error.new(
       :invalid_credentials_port,
       :construction,
       "credentials must be a module and configuration tuple"
     )}
  end

  defp transport_for(%__MODULE__{transports: transports}, %Selection{profile: profile}) do
    case Map.fetch(transports, BindingProfile.id(profile)) do
      {:ok, {module, config}} when is_atom(module) and not is_nil(module) ->
        {:ok, {module, config}}

      _missing ->
        {:error, Error.new(:transport_not_found, :transport, "selected transport was not found")}
    end
  end

  defp transport_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :request, 3) and
      function_exported?(module, :subscribe, 4) and function_exported?(module, :unsubscribe, 4)
  end

  defp resolve_credentials(
         %__MODULE__{credentials: {module, config}},
         %Selection{} = selection,
         %Context{} = context
       ) do
    case module.resolve(selection.security, selection.form, context, config) do
      {:ok, credential} ->
        {:ok, ExecutionContext.new(context, credential)}

      {:error, _external} ->
        {:error,
         Error.new(:credential_resolution_failed, :credentials, "credential resolution failed", %{
           request_id: Context.request_id(context),
           operation: selection.operation
         })}

      _invalid ->
        {:error,
         Error.new(
           :invalid_credentials_return,
           :credentials,
           "credential port returned an invalid value",
           %{
             request_id: Context.request_id(context),
             operation: selection.operation
           }
         )}
    end
  end

  defp transport_request({module, config}, request, execution_context) do
    case module.request(request, execution_context, config) do
      {:ok, %Result{request_id: request_id, operation: operation} = result}
      when request_id == request.request_id and operation == request.operation ->
        {:ok, result}

      {:ok, %Result{}} ->
        {:error,
         Error.new(
           :mismatched_transport_result,
           :transport,
           "transport result does not match the request",
           %{
             request_id: request.request_id,
             operation: request.operation
           }
         )}

      {:error, _external} ->
        {:error,
         Error.new(:transport_request_failed, :transport, "transport request failed", %{
           request_id: request.request_id,
           operation: request.operation
         })}

      _invalid ->
        {:error,
         Error.new(:invalid_transport_return, :transport, "transport returned an invalid value", %{
           request_id: request.request_id,
           operation: request.operation
         })}
    end
  end
end
