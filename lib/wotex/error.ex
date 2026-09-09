defmodule Wotex.Error do
  @moduledoc """
  Structured failure returned by Wotex public operations.

  Match on `code`, `phase`, and `path`. Human-readable messages may improve in
  compatible releases and are not a matching interface.

  `phase` locates the failing parse, value, schema, semantic, or encoding
  boundary. `path` is a JSON Pointer-style location within the input, while
  `details` carries machine-readable context specific to the error code.
  Constructors do not sanitize arbitrary diagnostic input; callers must bound
  and review it before reporting a failure. Make control-flow decisions only
  from documented stable fields.

  `Wotex.Error` implements the exception protocol for inspection and optional
  raising by a consumer, although Wotex public operations return it in tagged
  error tuples for expected invalid input. Messages and details must not be used
  to transport credentials, unbounded source documents, or consumer-specific
  policy. A validation error describes the package boundary; it is not an
  authorization result or a standards-certification record.
  """

  @type phase :: :parse | :value | :schema | :semantic | :encode
  @type t :: %__MODULE__{
          code: atom(),
          phase: phase(),
          path: String.t(),
          message: String.t(),
          details: map()
        }

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, path: "/", details: %{}]

  @doc false
  @spec new(atom(), phase(), String.t(), String.t(), map()) :: t()
  def new(code, phase, message, path \\ "/", details \\ %{})
      when is_atom(code) and is_atom(phase) and is_binary(message) and is_binary(path) and
             is_map(details) do
    %__MODULE__{code: code, phase: phase, message: message, path: path, details: details}
  end
end
