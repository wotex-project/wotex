defmodule Wotex.Form do
  @moduledoc """
  An immutable W3C WoT Form value.

  A Form declares where and how an Interaction Affordance may be used. Wotex
  requires a non-empty `href`, validates the shape of an optional `op`, and
  preserves all binding-specific and extension members. Relative references
  remain unresolved here because resolution depends on the enclosing Thing
  Description and installed binding.

  A valid Form is descriptive metadata. It does not select a transport,
  resolve credentials, authorize an interaction, or establish its outcome.

  Use `href/1` and `operations/1` or `operations/2` to inspect admitted fields;
  enclosing affordance modules supply the interaction context required for W3C
  default-operation rules.
  """

  alias Wotex.Value

  @type t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc """
  Builds a Form value. A non-empty `href` is required.

  Pass `for: :property`, `for: :action`, `for: :event`, or `for: :thing` to
  validate `op` against that TD 1.1 interaction context. The default
  `for: :generic` validates only the common Form definition.
  """
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []) do
    requirements = [
      {"href", &non_empty_binary?/1, "Form href must be non-empty"},
      {"op", &valid_operation?/1, "Form op must be a string or a list of strings when present"}
    ]

    with {:ok, form} <- Value.build(__MODULE__, map, requirements, :form, opts),
         :ok <- Wotex.ValueSchema.validate_form(map, Keyword.get(opts, :for, :generic)) do
      {:ok, form}
    end
  end

  @doc "Returns the complete preserved Form map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = form), do: Value.to_map(form)

  @doc "Returns the unresolved Form href."
  @spec href(t()) :: String.t()
  def href(%__MODULE__{value: value}), do: Map.fetch!(value, "href")

  @doc "Returns declared operation names in source order, or `[]` when `op` is absent."
  @spec operations(t()) :: [String.t()]
  def operations(%__MODULE__{value: %{"op" => operation}}) when is_binary(operation),
    do: [operation]

  def operations(%__MODULE__{value: %{"op" => operations}}) when is_list(operations),
    do: operations

  def operations(%__MODULE__{}), do: []

  @doc """
  Returns the effective operation names for an interaction context.

  Declared `op` members always win. When `op` is absent, TD 1.1 section 5.3.4.2
  assigns default operations by context: a Property Form defaults to
  `readproperty` and `writeproperty`, reduced to one of them when the affordance
  is `readOnly` or `writeOnly`; an Action Form defaults to `invokeaction`; an
  Event Form defaults to `subscribeevent` and `unsubscribeevent`. Thing-level
  and generic Forms have no default and return `[]`. A Property declared both
  `readOnly` and `writeOnly` is contradictory and receives no default.

  Options: `for:` (`:property`, `:action`, `:event`, `:thing`, or `:generic`),
  `read_only:` and `write_only:` booleans that apply to `:property` only.
  """
  @spec operations(t(), keyword()) :: [String.t()]
  def operations(%__MODULE__{value: %{"op" => _}} = form, _), do: operations(form)

  def operations(%__MODULE__{}, opts) when is_list(opts) do
    case Keyword.get(opts, :for, :generic) do
      :property ->
        property_defaults(
          Keyword.get(opts, :read_only, false) == true,
          Keyword.get(opts, :write_only, false) == true
        )

      :action ->
        ["invokeaction"]

      :event ->
        ["subscribeevent", "unsubscribeevent"]

      _ ->
        []
    end
  end

  defp property_defaults(true, true), do: []
  defp property_defaults(true, false), do: ["readproperty"]
  defp property_defaults(false, true), do: ["writeproperty"]
  defp property_defaults(false, false), do: ["readproperty", "writeproperty"]

  defp non_empty_binary?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0
  defp valid_operation?(nil), do: true
  defp valid_operation?(value) when is_binary(value), do: byte_size(value) > 0

  defp valid_operation?(values) when is_list(values),
    do: values != [] and Enum.all?(values, &(is_binary(&1) and byte_size(&1) > 0))

  defp valid_operation?(_), do: false
end
