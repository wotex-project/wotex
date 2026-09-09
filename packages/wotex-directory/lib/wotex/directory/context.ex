defmodule Wotex.Directory.Context do
  @moduledoc """
  Opaque consumer context passed to authorization and repository ports.

  The package interprets only `principal` as the subject to authorize. The two
  context values have no package-defined scope or persistence semantics.

  `authorization` can carry request-specific policy material, while
  `repository` can carry transaction, tenant, or tracing information for a
  repository adapter. Both values pass unchanged to consumer ports. This
  separation permits applications to propagate boundary context without
  coupling directory mechanics to an authentication framework or storage
  system.

  A principal is required and may be any non-`nil` term selected by the
  application. `new/2` returns a typed validation error for unknown options;
  `new!/2` is provided for trusted configuration paths where failure should
  raise.
  """

  alias Wotex.Directory.Error

  @enforce_keys [:principal]
  defstruct [:principal, authorization: nil, repository: nil]

  @type t :: %__MODULE__{
          principal: term(),
          authorization: term(),
          repository: term()
        }

  @spec new(term(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  @doc "Builds a request context with opaque authorization and repository values."
  def new(principal, options \\ [])

  def new(nil, _), do: {:error, Error.new(:invalid_context, :validation, :service)}

  def new(principal, options) when is_list(options) do
    allowed = [:authorization, :repository]

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) do
      {:ok,
       %__MODULE__{
         principal: principal,
         authorization: Keyword.get(options, :authorization),
         repository: Keyword.get(options, :repository)
       }}
    else
      {:error, Error.new(:invalid_context, :validation, :service)}
    end
  end

  def new(_, _), do: {:error, Error.new(:invalid_context, :validation, :service)}

  @spec new!(term(), keyword()) :: t()
  @doc "Builds a request context or raises the returned typed error."
  def new!(principal, options \\ []) do
    case new(principal, options) do
      {:ok, context} -> context
      {:error, error} -> raise error
    end
  end

  @spec valid?(term()) :: boolean()
  @doc "Reports whether a term is a request context with a non-nil principal."
  def valid?(%__MODULE__{principal: principal}), do: not is_nil(principal)
  def valid?(_), do: false
end
