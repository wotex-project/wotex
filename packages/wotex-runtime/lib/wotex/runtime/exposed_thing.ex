defmodule Wotex.Runtime.ExposedThing do
  @moduledoc """
  Binding-neutral callback dispatch for an exposed Thing.

  Interaction Affordance handlers are keyed by `{operation, affordance_name}`;
  Thing-level handlers are keyed directly by their operation atom. Every
  handler is an arity-two function receiving input and
  `Wotex.Runtime.Context`. Dispatch first checks that the operation and its
  Interaction Affordance or top-level Form are declared, then resolves the
  exact handler.

  The value owns no server, endpoint, authentication, authorization, or
  canonical Thing state. A consumer must enforce policy before dispatch and
  decide how handler results become protocol responses. Handler exceptions
  intentionally propagate to the caller so its supervision and error boundary
  remain authoritative.
  """

  alias Wotex.Runtime.{Context, Error}
  alias Wotex.ThingDescription

  @containers %{property: "properties", action: "actions", event: "events"}

  @type handler :: (term(), Context.t() -> term())
  @type t :: %__MODULE__{td: ThingDescription.t(), handlers: map()}

  @enforce_keys [:td, :handlers]
  defstruct [:td, :handlers]

  @doc "Builds an ExposedThing with explicit affordance and Thing-level handlers."
  @spec new(ThingDescription.t(), map()) ::
          {:ok, t()} | {:error, Error.t() | [Wotex.Error.t()]}
  def new(%ThingDescription{} = td, handlers) when is_map(handlers) do
    with {:ok, validated} <- ThingDescription.validate(td),
         :ok <- validate_handlers(handlers) do
      {:ok, %__MODULE__{td: validated, handlers: handlers}}
    end
  end

  def new(_, _) do
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
         :ok <- require_affordance_type(type),
         :ok <- affordance_exists(exposed.td, type, name),
         {:ok, handler} <- fetch_handler(exposed.handlers, operation, name) do
      handler.(input, context)
    end
  end

  def dispatch(%__MODULE__{}, _, _, _, _) do
    {:error, Error.new(:invalid_dispatch_input, :dispatch, "dispatch input is invalid")}
  end

  def dispatch(_, _, _, _, _) do
    {:error, Error.new(:invalid_exposed_thing, :dispatch, "an ExposedThing is required")}
  end

  @doc "Checks a top-level Form declaration and invokes its operation handler."
  @spec dispatch_thing(t(), atom(), term(), Context.t()) :: term() | {:error, Error.t()}
  def dispatch_thing(%__MODULE__{} = exposed, operation, input, %Context{} = context) do
    with {:ok, :thing} <- operation_type(operation),
         :ok <- thing_operation_exists(exposed.td, operation),
         {:ok, handler} <- fetch_thing_handler(exposed.handlers, operation) do
      handler.(input, context)
    else
      {:ok, _} ->
        {:error, Error.new(:unsupported_operation, :dispatch, "operation is not Thing-level")}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def dispatch_thing(%__MODULE__{}, _, _, _) do
    {:error, Error.new(:invalid_dispatch_input, :dispatch, "dispatch input is invalid")}
  end

  def dispatch_thing(_, _, _, _) do
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
          Wotex.Runtime.interaction_type(operation) not in [:property, :action, :event]

        {operation, handler} when is_atom(operation) and is_function(handler, 2) ->
          Wotex.Runtime.interaction_type(operation) != :thing

        _ ->
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
    case Wotex.Runtime.interaction_type(operation) do
      nil -> {:error, Error.new(:unsupported_operation, :dispatch, "operation is not supported")}
      type -> {:ok, type}
    end
  end

  defp require_affordance_type(type) when type in [:property, :action, :event], do: :ok

  defp require_affordance_type(:thing) do
    {:error, Error.new(:unsupported_operation, :dispatch, "operation is Thing-level")}
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

  defp thing_operation_exists(td, operation) do
    declared? =
      td
      |> ThingDescription.to_map()
      |> Map.get("forms", [])
      |> Enum.any?(fn
        %{"op" => operations} when is_list(operations) -> operation_string(operation) in operations
        %{"op" => declared} when is_binary(declared) -> operation_string(operation) == declared
        _ -> false
      end)

    if declared? do
      :ok
    else
      {:error,
       Error.new(:thing_operation_not_found, :dispatch, "Thing-level operation was not found", %{
         operation: operation
       })}
    end
  end

  defp operation_string(operation), do: Atom.to_string(operation)

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

  defp fetch_thing_handler(handlers, operation) do
    case Map.fetch(handlers, operation) do
      {:ok, handler} ->
        {:ok, handler}

      :error ->
        {:error,
         Error.new(:handler_not_found, :dispatch, "handler was not found", %{
           operation: operation
         })}
    end
  end
end
