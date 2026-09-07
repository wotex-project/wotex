defmodule WotexContinuum.Error do
  @moduledoc """
  Typed validation, codec, or lifecycle error.

  `code` names the stable failure, `phase` names the stage that produced it,
  and `details` carries structured context. `path` is an RFC 6901 JSON Pointer
  string rooted at `"/"`, such as `"/extensions/urn:example:payload/0"`, so a
  consumer can address the exact wire location without parsing a message. It is
  `nil` when no wire location applies, for example a keyword-option failure.

  Match on `code`, `phase`, and `path`. Messages may improve in compatible
  releases and are not a matching interface.
  """

  alias Wotex.JSON

  @root "/"

  @typedoc "Processing stage that produced the error."
  @type phase :: :decode | :validation | :encode | :lifecycle | :compatibility | :limits

  @typedoc "One unescaped JSON Pointer path segment."
  @type segment :: String.t() | non_neg_integer()

  @type t :: %__MODULE__{
          code: atom(),
          phase: phase(),
          path: String.t() | nil,
          message: String.t(),
          details: map()
        }

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, path: @root, details: %{}]

  @doc "Returns the JSON Pointer that addresses a document root."
  @spec root() :: String.t()
  def root, do: @root

  @doc """
  Returns the JSON Pointer of a child member or list index.

  Member names are escaped as RFC 6901 requires, so `~` becomes `~0` and `/`
  becomes `~1`.
  """
  @spec child(String.t(), segment()) :: String.t()
  def child(@root, segment), do: @root <> escape(segment)
  def child(path, segment) when is_binary(path), do: path <> @root <> escape(segment)

  @doc "Builds a typed error with an explicit code, phase, message, and path."
  @spec new(atom(), phase(), String.t(), String.t() | nil, map()) :: t()
  def new(code, phase, message, path \\ @root, details \\ %{})
      when is_atom(code) and is_atom(phase) and is_binary(message) and
             (is_binary(path) or is_nil(path)) and is_map(details) do
    %__MODULE__{code: code, phase: phase, message: message, path: path, details: details}
  end

  @doc false
  @spec error(atom(), phase(), String.t() | nil, String.t(), map()) :: {:error, t()}
  def error(code, phase, path, message, details \\ %{}) do
    {:error, new(code, phase, message, path, details)}
  end

  @doc "Re-roots an error path under a parent JSON Pointer."
  @spec prefix(t(), String.t()) :: t()
  def prefix(%__MODULE__{path: nil} = error, parent) when is_binary(parent), do: error
  def prefix(%__MODULE__{} = error, @root), do: error

  def prefix(%__MODULE__{path: @root} = error, parent) when is_binary(parent),
    do: %{error | path: parent}

  def prefix(%__MODULE__{} = error, parent) when is_binary(parent),
    do: %{error | path: parent <> error.path}

  @doc "Re-roots an error path under one parent segment."
  @spec prepend(t(), segment()) :: t()
  def prepend(%__MODULE__{} = error, segment), do: prefix(error, child(@root, segment))

  @doc """
  Translates a Wotex core error into the equivalent continuum error.

  Core admission codes are mapped to the continuum vocabulary documented in
  WCT.01; the JSON Pointer path is preserved and the original code is kept in
  `details`.
  """
  @spec from_core(Wotex.Error.t()) :: t()
  def from_core(%Wotex.Error{} = error) do
    {code, phase} = translate(error.code)

    new(code, phase, error.message, error.path, Map.put(error.details, :core_code, error.code))
  end

  @impl Exception
  def message(%__MODULE__{message: message, path: nil}), do: message
  def message(%__MODULE__{message: message, path: @root}), do: message
  def message(%__MODULE__{message: message, path: path}), do: "#{path}: #{message}"

  defp translate(:byte_limit_exceeded), do: {:limit_exceeded, :limits}
  defp translate(:depth_limit_exceeded), do: {:limit_exceeded, :limits}
  defp translate(:node_limit_exceeded), do: {:limit_exceeded, :limits}
  defp translate(:string_limit_exceeded), do: {:limit_exceeded, :limits}
  defp translate(:collection_limit_exceeded), do: {:limit_exceeded, :limits}
  defp translate(:invalid_limit), do: {:invalid_limit, :limits}
  defp translate(:invalid_options), do: {:invalid_options, :limits}
  defp translate(:invalid_string), do: {:invalid_utf8, :decode}
  defp translate(:duplicate_member), do: {:duplicate_field, :decode}
  defp translate(:non_string_key), do: {:invalid_key, :decode}
  defp translate(:invalid_json), do: {:invalid_json, :decode}
  defp translate(:invalid_json_value), do: {:invalid_json_value, :decode}
  defp translate(_), do: {:invalid_type, :decode}

  defp escape(segment) when is_integer(segment), do: Integer.to_string(segment)
  defp escape(segment) when is_binary(segment), do: JSON.pointer_segment(segment)
end
