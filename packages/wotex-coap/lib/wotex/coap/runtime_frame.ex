defmodule Wotex.CoAP.RuntimeFrame do
  @moduledoc """
  Validates complete native Observe reports before Runtime content decoding.

  The relay supplies a `Wotex.CoAP.Message` and its five-field report metadata.
  Validation reconstructs the observation metadata and checks complete-body
  consistency before `Wotex.CoAP.Mapping` decodes JSON, text, or binary content.
  A successful result preserves the validated metadata beside the decoded value.

  Native errors pass a separate structural check: details may contain only the
  library-owned code, reason, or limit keys with atom or integer values.
  Unexpected frame or error shapes become `:invalid_runtime_frame` errors;
  arbitrary native output is not copied into Runtime diagnostics. This helper
  is pure and owns no receiver, queue, session, or subscription lifecycle.
  """

  alias Wotex.CoAP.{Error, Mapping, Message}
  alias Wotex.CoAP.Observation.Report

  @doc false
  @spec validate(term(), term()) :: :ok | {:error, Error.t()}
  def validate(%Message{} = message, metadata) when is_map(metadata) and map_size(metadata) == 5 do
    with {:ok, report} <- Report.new(%{message | payload: <<>>}, 0),
         {:ok, _} <- Report.complete(report, message),
         true <- report.metadata === metadata,
         do: :ok,
         else: (_ -> {:error, Error.new(:invalid_runtime_frame)})
  end

  def validate(_, _), do: {:error, Error.new(:invalid_runtime_frame)}

  @doc false
  @spec decode(map(), term(), term()) :: {:ok, term(), map()} | {:error, Error.t()}
  def decode(mapping, message, metadata) do
    with :ok <- validate(message, metadata),
         {:ok, value} <- Mapping.decode(mapping, message),
         do: {:ok, value, metadata}
  end

  @doc false
  @spec error(term()) :: Error.t()
  def error(%Error{code: code, field: field, details: details} = error)
      when map_size(error) == 6 and is_atom(code) and (is_nil(field) or is_atom(field)) and
             is_map(details) and map_size(details) <= 8 and is_boolean(error.retryable) and
             error.effect in [:none, :unknown] do
    if Enum.all?(details, fn {key, value} ->
         key in [:code, :reason, :limit] and (is_atom(value) or is_integer(value))
       end),
       do: error,
       else: Error.new(:invalid_runtime_frame)
  end

  def error(_), do: Error.new(:invalid_runtime_frame)
end
