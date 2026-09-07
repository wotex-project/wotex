defmodule Wotex.Directory.Context do
  @moduledoc """
  Opaque consumer context passed to authorization and repository ports.

  The package interprets only `principal` as the subject to authorize. The two
  context values have no package-defined scope or persistence semantics.
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

  def new(nil, _options), do: {:error, Error.new(:invalid_context, :validation, :service)}

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

  def new(_principal, _options), do: {:error, Error.new(:invalid_context, :validation, :service)}

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
  def valid?(_context), do: false
end
