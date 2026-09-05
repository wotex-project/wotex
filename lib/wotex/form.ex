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

  @doc "Returns declared operation names in source order."
  @spec operations(t()) :: [String.t()]
  def operations(%__MODULE__{value: %{"op" => operation}}) when is_binary(operation),
    do: [operation]

  def operations(%__MODULE__{value: %{"op" => operations}}) when is_list(operations),
    do: operations

  def operations(%__MODULE__{}), do: []

  defp non_empty_binary?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0
  defp valid_operation?(nil), do: true
  defp valid_operation?(value) when is_binary(value), do: byte_size(value) > 0

  defp valid_operation?(values) when is_list(values),
    do: values != [] and Enum.all?(values, &(is_binary(&1) and byte_size(&1) > 0))

  defp valid_operation?(_value), do: false
end
