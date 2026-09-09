defmodule Wotex.CoAP.Security.CRLCache do
  @moduledoc false

  require Record

  Record.defrecordp(
    :distribution_point,
    :DistributionPoint,
    Record.extract(:DistributionPoint, from_lib: "public_key/include/public_key.hrl")
  )

  @doc false
  @spec lookup(term(), term(), term()) :: [binary()] | :not_available
  def lookup(distribution_point(cRLIssuer: issuer), default_issuer, reference) do
    selected = select(if(issuer == :asn1_NOVALUE, do: default_issuer, else: issuer), reference)
    if selected == [], do: :not_available, else: selected
  end

  def lookup(_, _, _), do: :not_available

  @doc false
  @spec select(term(), term()) :: [binary()]
  def select({:rdnSequence, _} = issuer, {:supplied, crls}) do
    normalized = :public_key.pkix_normalize_name(issuer)

    Enum.filter(crls, fn bytes ->
      issuer = :public_key.pkix_crl_issuer(bytes)
      :public_key.pkix_normalize_name(issuer) == normalized
    end)
  rescue
    _ -> []
  end

  def select(names, reference) when is_list(names) do
    names
    |> Enum.flat_map(fn
      {:directoryName, name} -> select(name, reference)
      _ -> []
    end)
    |> Enum.uniq()
  end

  def select(_, _), do: []

  @doc false
  @spec fresh_crl(term(), binary()) :: binary()
  def fresh_crl(_, bytes), do: bytes
end
