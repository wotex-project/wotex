defmodule Wotex.Runtime.Context do
  @moduledoc """
  Immutable caller-supplied interaction context.

  The runtime neither generates `request_id` nor reads a clock. A deadline is
  an absolute value interpreted by the supplied credential and transport ports.

  Metadata carries non-secret correlation information such as trace ids or
  actor references. It is passed through interaction planning without policy
  interpretation. Do not place credentials in metadata; ephemeral credential
  material has a separate execution-only value.
  """

  alias Wotex.Runtime.Error

  @type deadline :: DateTime.t() | integer() | nil
  @type t :: %__MODULE__{
          request_id: String.t(),
          deadline: deadline(),
          metadata: map()
        }

  @enforce_keys [:request_id]
  defstruct [:request_id, :deadline, metadata: %{}]

  @doc "Builds a validated interaction context."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    request_id = Keyword.get(opts, :request_id)
    deadline = Keyword.get(opts, :deadline)
    metadata = Keyword.get(opts, :metadata, %{})

    cond do
      not (is_binary(request_id) and byte_size(String.trim(request_id)) > 0) ->
        {:error,
         Error.new(:invalid_request_id, :construction, "request_id must be a non-empty string")}

      not valid_deadline?(deadline) ->
        {:error,
         Error.new(
           :invalid_deadline,
           :construction,
           "deadline must be an absolute integer, DateTime, or nil"
         )}

      not is_map(metadata) ->
        {:error, Error.new(:invalid_metadata, :construction, "metadata must be a map")}

      true ->
        {:ok, %__MODULE__{request_id: request_id, deadline: deadline, metadata: metadata}}
    end
  end

  def new(_opts) do
    {:error,
     Error.new(:invalid_context_options, :construction, "context options must be a keyword list")}
  end

  @doc "Builds a context and raises `Wotex.Runtime.Error` when invalid."
  @spec new!(keyword()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, context} -> context
      {:error, error} -> raise error
    end
  end

  @doc "Returns the caller-supplied request id."
  @spec request_id(t()) :: String.t()
  def request_id(%__MODULE__{request_id: request_id}), do: request_id

  @doc "Returns the optional caller-supplied absolute deadline."
  @spec deadline(t()) :: deadline()
  def deadline(%__MODULE__{deadline: deadline}), do: deadline

  @doc "Returns caller-supplied non-credential metadata."
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{metadata: metadata}), do: metadata

  defp valid_deadline?(nil), do: true
  defp valid_deadline?(deadline) when is_integer(deadline), do: true
  defp valid_deadline?(%DateTime{}), do: true
  defp valid_deadline?(_deadline), do: false
end
