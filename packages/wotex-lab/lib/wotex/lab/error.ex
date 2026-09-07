defmodule Wotex.Lab.Error do
  @moduledoc """
  Structured errors at Lab construction, composition and adapter boundaries.

  The shape follows the WoTEx family convention: `code`, `phase`, `path`,
  `message`, `details`, plus a retry `class` for transport-facing failures so
  the runtime can carry it as a cause.
  """

  @type class :: :timeout | :unavailable | :rate_limited | :protocol | :permanent | nil

  @typedoc "Stable code and phase; the explanatory message contains no supplied payload."
  @type t :: %__MODULE__{
          code: atom(),
          phase: atom(),
          path: String.t() | nil,
          message: String.t(),
          details: map(),
          class: class()
        }

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, path: nil, details: %{}, class: nil]

  @doc "Builds an error without embedding caller configuration or secrets."
  @spec new(atom(), atom(), String.t(), keyword()) :: t()
  def new(code, phase, message, opts \\ []) when is_atom(code) and is_atom(phase) do
    %__MODULE__{
      code: code,
      phase: phase,
      message: message,
      path: Keyword.get(opts, :path),
      details: Keyword.get(opts, :details, %{}),
      class: Keyword.get(opts, :class)
    }
  end
end
