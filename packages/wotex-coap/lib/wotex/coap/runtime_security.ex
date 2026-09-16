defmodule Wotex.CoAP.RuntimeSecurity do
  @moduledoc """
  Selects explicit native credential custody for one Runtime CoAP route.

  A plain UDP route accepts no credential. DTLS and OSCORE routes require one
  validated `Wotex.CoAP.Security` value from either the immediate execution
  context or the consumer's transport configuration. Supplying both is
  ambiguous and fails before acquisition. The selected mode never falls back
  to another security adapter.

  This pure helper returns connection options without retaining a Runtime
  request or execution context. The transport permits immediate credentials
  only for scoped unary calls; persistent observations require configured
  credentials. Construction neither starts SSL nor tests backend availability.
  """

  alias Wotex.CoAP.{Error, Security}

  @doc false
  @spec options(:coap | :coaps, term(), keyword()) :: {:ok, keyword()} | {:error, Error.t()}
  def options(:coap, immediate, config) do
    case {immediate, Keyword.fetch(config, :security)} do
      {nil, :error} -> {:ok, [scheme: :coap]}
      {nil, {:ok, %Security{mode: :oscore} = security}} -> authenticated(:coap, security)
      {%Security{mode: :oscore} = security, :error} -> authenticated(:coap, security)
      _ -> failure()
    end
  end

  def options(:coaps, immediate, config) do
    case {immediate, Keyword.fetch(config, :security)} do
      {nil, {:ok, %Security{mode: mode} = security}} when mode in [:dtls_psk, :dtls_pki] ->
        authenticated(:coaps, security)

      {%Security{mode: mode} = security, :error} when mode in [:dtls_psk, :dtls_pki] ->
        authenticated(:coaps, security)

      _ ->
        failure()
    end
  end

  def options(_, _, _), do: failure()

  defp authenticated(scheme, security) do
    with :ok <- Security.validate(security),
         do: {:ok, [scheme: scheme, security: security]}
  end

  defp failure, do: {:error, Error.new(:invalid_security)}
end
