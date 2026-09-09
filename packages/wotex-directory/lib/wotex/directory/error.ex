defmodule Wotex.Directory.Error do
  @moduledoc """
  Deterministic, redacted failure returned by directory operations.

  Callers match on `code`, `phase`, and `path`. `phase` names the stage that
  refused the request, `path` is a JSON Pointer into the submitted document
  when one applies, and `details` carries the directory `operation` and, when
  the failure concerns one entry, its `identifier`.

  Human-readable messages are deliberately free of Thing Description bodies,
  principals, adapter state, credentials, and unknown port terms.

  `new/4` derives its message from the supported code vocabulary. Callers of
  this low-level constructor must supply valid phases and operations and safe
  details; it does not redact arbitrary caller-supplied details. The facade
  normalizes returned port failures without retaining unknown reasons. Port
  implementations remain responsible for exceptions, which the facade does
  not rescue.
  """

  @type code ::
          :invalid_service
          | :invalid_context
          | :invalid_request
          | :invalid_thing_description
          | :identifier_mismatch
          | :not_found
          | :expired
          | :forbidden
          | :conflict
          | :collection_changed
          | :unsupported_query_profile
          | :invalid_page
          | :authorization_failure
          | :repository_failure
          | :clock_failure
          | :clock_regression
          | :identifier_failure

  @type phase ::
          :configuration
          | :validation
          | :authorization
          | :clock
          | :identifier
          | :repository
          | :listing
          | :patch
          | :expiry

  @type operation ::
          :service
          | :register
          | :get
          | :replace
          | :patch
          | :delete
          | :event
          | :list
          | :expire
          | :introduction

  @type t :: %__MODULE__{
          code: code(),
          phase: phase(),
          path: String.t() | nil,
          message: String.t(),
          details: map()
        }

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, path: nil, details: %{}]

  @doc """
  Builds a redacted error with a stable code, phase, and directory operation.

  `:identifier` and `:details` are merged into `details`; `:path` is a JSON
  Pointer rooted at `/` and stays `nil` when no submitted member is at fault.
  """
  @spec new(code(), phase(), operation(), keyword()) :: t()
  def new(code, phase, operation, options \\ [])
      when is_atom(code) and is_atom(phase) and is_atom(operation) and is_list(options) do
    %__MODULE__{
      code: code,
      phase: phase,
      path: Keyword.get(options, :path),
      message: message_for(code),
      details:
        options
        |> Keyword.get(:details, %{})
        |> Map.put(:operation, operation)
        |> put_identifier(Keyword.get(options, :identifier))
    }
  end

  @doc "Returns the deterministic message for a stable error code."
  @spec message_for(code()) :: String.t()
  def message_for(:invalid_service), do: "directory service configuration is invalid"
  def message_for(:invalid_context), do: "directory request context is invalid"
  def message_for(:invalid_request), do: "directory request is invalid"
  def message_for(:invalid_thing_description), do: "Thing Description is invalid"

  def message_for(:identifier_mismatch),
    do: "Thing Description identifier does not match the target"

  def message_for(:not_found), do: "directory entry was not found"
  def message_for(:expired), do: "directory entry is expired"
  def message_for(:forbidden), do: "directory operation is not authorized"
  def message_for(:conflict), do: "directory operation conflicts with current state"
  def message_for(:collection_changed), do: "directory collection changed during pagination"
  def message_for(:unsupported_query_profile), do: "directory query profile is unsupported"
  def message_for(:invalid_page), do: "directory repository returned an invalid page"
  def message_for(:authorization_failure), do: "directory authorization port failed"
  def message_for(:repository_failure), do: "directory repository port failed"
  def message_for(:clock_failure), do: "directory clock port failed"
  def message_for(:clock_regression), do: "directory clock precedes registration history"
  def message_for(:identifier_failure), do: "directory identifier port failed"

  defp put_identifier(details, nil), do: details
  defp put_identifier(details, identifier), do: Map.put(details, :identifier, identifier)
end
