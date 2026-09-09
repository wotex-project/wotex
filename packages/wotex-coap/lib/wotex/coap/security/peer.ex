defmodule Wotex.CoAP.Security.Peer do
  @moduledoc false

  alias Wotex.CoAP.Security.PKI
  require Record

  Record.defrecordp(
    :certificate,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :tbs,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :extension,
    :Extension,
    Record.extract(:Extension, from_lib: "public_key/include/public_key.hrl")
  )

  @doc false
  @spec verify(term(), term(), term()) ::
          {:valid | :unknown, term()}
          | {:fail,
             :invalid_peer_certificate
             | :invalid_peer_usage
             | :peer_identity_mismatch
             | :weak_peer_key}
  def verify(_, {:bad_cert, _}, _), do: {:fail, :invalid_peer_certificate}
  def verify(_, {:extension, _}, identity), do: {:unknown, identity}

  def verify(cert, :valid, identity) do
    if PKI.strong_certificate?(cert), do: {:valid, identity}, else: {:fail, :weak_peer_key}
  end

  def verify(cert, :valid_peer, identity) do
    cond do
      not PKI.valid_identity?(identity) -> {:fail, :peer_identity_mismatch}
      not PKI.strong_certificate?(cert) -> {:fail, :weak_peer_key}
      not usage?(cert) -> {:fail, :invalid_peer_usage}
      not identity?(cert, identity) -> {:fail, :peer_identity_mismatch}
      true -> {:valid, identity}
    end
  end

  def verify(_, _, _), do: {:fail, :invalid_peer_certificate}

  defp usage?(cert) do
    usage = value(cert, {2, 5, 29, 15})
    purposes = value(cert, {2, 5, 29, 37})
    :digitalSignature in usage and {1, 3, 6, 1, 5, 5, 7, 3, 1} in purposes
  end

  defp identity?(cert, {:dns, expected}) do
    Enum.any?(value(cert, {2, 5, 29, 17}), fn
      {:dNSName, name} when is_list(name) ->
        candidate = List.to_string(name)

        PKI.valid_identity?({:dns, candidate}) and
          String.downcase(candidate) == String.downcase(expected)

      _ ->
        false
    end)
  end

  defp identity?(cert, {:ip, address}) do
    expected =
      case tuple_size(address) do
        4 -> :erlang.list_to_binary(Tuple.to_list(address))
        8 -> for word <- Tuple.to_list(address), into: <<>>, do: <<word::16>>
      end

    {:iPAddress, expected} in value(cert, {2, 5, 29, 17})
  end

  defp value(certificate(tbsCertificate: tbs(extensions: extensions)), oid)
       when is_list(extensions) do
    Enum.find_value(extensions, [], fn
      extension(extnID: ^oid, extnValue: value) when is_list(value) -> value
      _ -> nil
    end)
  end

  defp value(_, _), do: []
end
