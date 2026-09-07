defmodule Wotex.Runtime.Error do
  @moduledoc """
  Stable runtime failure.

  Match on `code`, `phase`, and `class`. Messages may improve in compatible
  releases. External return values are deliberately not copied into errors
  because they can contain credential or transport internals; when a port
  returns its own structured error, only its atom `code`, `phase`, and `class`
  are retained under `details.cause`.

  `class` is the retry classification consumed by `Wotex.Runtime.Retry`:
  `:timeout`, `:unavailable`, and `:rate_limited` are transient; `:protocol`
  and `:permanent` are not; `nil` means the failure was not classified and is
  treated as non-retryable.
  """

  @type phase ::
          :construction
          | :selection
          | :credentials
          | :transport
          | :dispatch
          | :subscription

  @type class :: :timeout | :unavailable | :rate_limited | :protocol | :permanent | nil

  @type t :: %__MODULE__{
          code: atom(),
          phase: phase(),
          class: class(),
          message: String.t(),
          details: map()
        }

  @classes [:timeout, :unavailable, :rate_limited, :protocol, :permanent]

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, class: nil, details: %{}]

  @doc false
  @spec new(atom(), phase(), String.t(), map()) :: t()
  def new(code, phase, message, details \\ %{})
      when is_atom(code) and is_atom(phase) and is_binary(message) and is_map(details) do
    %__MODULE__{code: code, phase: phase, message: message, details: details}
  end

  @doc "Returns the retry class, `nil` when the failure is unclassified."
  @spec class(t()) :: class()
  def class(%__MODULE__{class: class}), do: class

  @doc false
  @spec with_cause(t(), term()) :: t()
  def with_cause(%__MODULE__{} = error, %{__struct__: module, code: code} = external)
      when is_atom(code) do
    phase = safe_atom(Map.get(external, :phase))
    class = safe_class(Map.get(external, :class))
    cause = %{module: module, code: code, phase: phase, class: class}
    %{error | class: class, details: Map.put(error.details, :cause, cause)}
  end

  def with_cause(%__MODULE__{} = error, _external), do: error

  defp safe_atom(value) when is_atom(value), do: value
  defp safe_atom(_value), do: nil

  defp safe_class(value) when value in @classes, do: value
  defp safe_class(_value), do: nil
end
