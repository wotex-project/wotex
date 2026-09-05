defmodule Wotex.Directory.Error do
  @moduledoc """
  Deterministic, redacted failure returned by directory operations.

  Callers match on `code`; human-readable messages are deliberately free of
  Thing Description bodies, principals, adapter state, and unknown port terms.
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
          operation: operation(),
          identifier: String.t() | nil,
          message: String.t(),
          details: map()
        }

  defexception [:code, :operation, :identifier, :message, details: %{}]

  @spec new(code(), operation(), keyword()) :: t()
  @doc "Builds a redacted error with a stable code and operation."
  def new(code, operation, options \\ []) do
    %__MODULE__{
      code: code,
      operation: operation,
      identifier: Keyword.get(options, :identifier),
      message: message_for(code),
      details: Keyword.get(options, :details, %{})
    }
  end

  @spec message_for(code()) :: String.t()
  @doc "Returns the deterministic message for a stable error code."
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
end
