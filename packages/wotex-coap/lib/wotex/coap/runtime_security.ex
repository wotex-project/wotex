defmodule Wotex.CoAP.RuntimeSecurity do
  @moduledoc """
  Selects explicit native credential custody for one Runtime CoAP route.

  A UDP route accepts no credential. A DTLS route requires one validated
  `Wotex.CoAP.Security` value from either the immediate execution context or
  the consumer's transport configuration. Supplying both is ambiguous and
  fails before acquisition. The selected scheme never falls back to UDP.

  This pure helper returns connection options without retaining a Runtime
  request or execution context. The transport permits immediate credentials
  only for scoped unary calls; persistent observations require configured
  credentials. Construction neither starts SSL nor tests backend availability.
  """

  alias Wotex.CoAP.{Error, Security}

  @doc false
  @spec options(:coap | :coaps, term(), keyword()) :: {:ok, keyword()} | {:error, Error.t()}
  def options(:coap, nil, config) do
    if Keyword.has_key?(config, :security), do: failure(), else: {:ok, [scheme: :coap]}
  end

  def options(:coaps, immediate, config) do
    case {immediate, Keyword.fetch(config, :security)} do
      {nil, {:ok, security}} -> authenticated(security)
      {%Security{} = security, :error} -> authenticated(security)
      _ -> failure()
    end
  end

  def options(_, _, _), do: failure()

  defp authenticated(security) do
    with :ok <- Security.validate(security),
         do: {:ok, [scheme: :coaps, security: security]}
  end

  defp failure, do: {:error, Error.new(:invalid_security)}
end
