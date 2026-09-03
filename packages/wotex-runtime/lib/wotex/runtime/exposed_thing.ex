defmodule Wotex.Runtime.ExposedThing do
  @moduledoc """
  Binding-neutral callback dispatch for an exposed Thing.

  Handlers are keyed by `{operation, affordance_name}` and must be arity-two
  functions receiving input and `Wotex.Runtime.Context`. Dispatch first checks
  that the operation is supported, the Interaction Affordance exists in the
  Thing Description, and the exact handler was registered.

  The value owns no server, endpoint, authentication, authorization, or
  canonical Thing state. A consumer must enforce policy before dispatch and
  decide how handler results become protocol responses. Handler exceptions
  intentionally propagate to the caller so its supervision and error boundary
  remain authoritative.
  """

  alias Wotex.Runtime.{Context, Error}
  alias Wotex.ThingDescription

  @operation_types %{
    readproperty: :property,
    writeproperty: :property,
    observeproperty: :property,
    unobserveproperty: :property,
    invokeaction: :action,
    queryaction: :action,
    cancelaction: :action,
    subscribeevent: :event,
    unsubscribeevent: :event
  }

  @containers %{property: "properties", action: "actions", event: "events"}

  @type handler :: (term(), Context.t() -> term())
  @type t :: %__MODULE__{td: ThingDescription.t(), handlers: map()}

  @enforce_keys [:td, :handlers]
  defstruct [:td, :handlers]

  @doc "Builds an ExposedThing with handlers keyed by `{operation, affordance_name}`."
  @spec new(ThingDescription.t(), map()) ::
          {:ok, t()} | {:error, Error.t() | [Wotex.Error.t()]}
  def new(%ThingDescription{} = td, handlers) when is_map(handlers) do
    with {:ok, validated} <- ThingDescription.validate(td),
         :ok <- validate_handlers(handlers) do
      {:ok, %__MODULE__{td: validated, handlers: handlers}}
    end
  end

  def new(_td, _handlers) do
    {:error,
     Error.new(
       :invalid_exposed_thing,
       :construction,
       "a Thing Description and handler map are required"
     )}
  end

  @doc "Checks the affordance and invokes the exact registered handler."
  @spec dispatch(t(), atom(), String.t(), term(), Context.t()) :: term() | {:error, Error.t()}
  def dispatch(%__MODULE__{} = exposed, operation, name, input, %Context{} = context)
      when is_binary(name) do
    with {:ok, type} <- operation_type(operation),
         :ok <- affordance_exists(exposed.td, type, name),
         {:ok, handler} <- fetch_handler(exposed.handlers, operation, name) do
      handler.(input, context)
    end
  end

  def dispatch(%__MODULE__{}, _operation, _name, _input, _context) do
    {:error, Error.new(:invalid_dispatch_input, :dispatch, "dispatch input is invalid")}
  end

  def dispatch(_exposed, _operation, _name, _input, _context) do
    {:error, Error.new(:invalid_exposed_thing, :dispatch, "an ExposedThing is required")}
  end

  @doc "Returns the immutable Thing Description."
  @spec thing_description(t()) :: ThingDescription.t()
  def thing_description(%__MODULE__{td: td}), do: td

  defp validate_handlers(handlers) do
    invalid =
      Enum.find(handlers, fn
        {{operation, name}, handler}
        when is_atom(operation) and is_binary(name) and is_function(handler, 2) ->
          not Map.has_key?(@operation_types, operation)

        _entry ->
          true
      end)

    if invalid do
      {:error,
       Error.new(
         :invalid_handler,
         :construction,
         "handlers must use supported operation/name keys and arity-two functions"
       )}
    else
      :ok
    end
  end

  defp operation_type(operation) do
    case Map.fetch(@operation_types, operation) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, Error.new(:unsupported_operation, :dispatch, "operation is not supported")}
    end
  end

  defp affordance_exists(td, type, name) do
    document = ThingDescription.to_map(td)

    if is_map(get_in(document, [@containers[type], name])) do
      :ok
    else
      {:error,
       Error.new(:affordance_not_found, :dispatch, "Interaction Affordance was not found", %{
         affordance_type: type,
         affordance_name: name
       })}
    end
  end

  defp fetch_handler(handlers, operation, name) do
    case Map.fetch(handlers, {operation, name}) do
      {:ok, handler} ->
        {:ok, handler}

      :error ->
        {:error,
         Error.new(:handler_not_found, :dispatch, "handler was not found", %{
           operation: operation,
           affordance_name: name
         })}
    end
  end
end
