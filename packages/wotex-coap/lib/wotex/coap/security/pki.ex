defmodule Wotex.CoAP.Security.PKI do
  @moduledoc false

  import Bitwise
  alias Wotex.CoAP.Error
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
    :public_info,
    :OTPSubjectPublicKeyInfo,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :rsa_public,
    :RSAPublicKey,
    Record.extract(:RSAPublicKey, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :rsa_private,
    :RSAPrivateKey,
    Record.extract(:RSAPrivateKey, from_lib: "public_key/include/public_key.hrl")
  )

  @minimum_modulus 1 <<< 2047

  @doc false
  @spec validate(map()) :: :ok | {:error, Error.t()}
  def validate(values) do
    with {:ok, roots} <- binaries(values.trust_roots, 8, []),
         {:ok, crls} <- binaries(values.crls, 8, []),
         true <- binary?(values.certificate) and binary?(values.private_key),
         true <- valid_identity?(values.server_identity),
         true <-
           Enum.sum(
             Enum.map(roots ++ crls ++ [values.certificate, values.private_key], &byte_size/1)
           ) <=
             1_048_576,
         true <- Enum.all?(roots, &strong_certificate?/1),
         true <- Enum.all?(crls, &valid_crl?/1),
         {:ok, public} <- certificate_key(values.certificate),
         {:ok, _, private} <- private_key(values.private_key),
         true <- matching?(public, private),
         do: :ok,
         else: (_ -> failure())
  end

  @doc false
  @spec private_key(binary()) :: {:ok, :RSAPrivateKey | :PrivateKeyInfo, tuple()} | :error
  def private_key(bytes) do
    Enum.find_value([:RSAPrivateKey, :PrivateKeyInfo], :error, &decode_private(&1, bytes))
  end

  defp decode_private(type, bytes) do
    with true <- der?(bytes),
         key = :public_key.der_decode(type, bytes),
         true <- strong_private?(key),
         do: {:ok, type, key},
         else: (_ -> nil)
  rescue
    _ -> nil
  end

  @doc false
  @spec strong_certificate?(binary() | tuple()) :: boolean()
  def strong_certificate?(bytes) when is_binary(bytes), do: match?({:ok, _}, certificate_key(bytes))

  def strong_certificate?(certificate(tbsCertificate: value)),
    do:
      match?(
        rsa_public(modulus: modulus) when is_integer(modulus) and modulus >= @minimum_modulus,
        public_key(value)
      )

  def strong_certificate?(_), do: false

  @doc false
  @spec valid_identity?(term()) :: boolean()
  def valid_identity?({:dns, name}) when is_binary(name) and byte_size(name) in 1..253 do
    name
    |> String.split(".")
    |> Enum.all?(fn label ->
      byte_size(label) in 1..63 and
        Regex.match?(~r/\A[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\z/, label)
    end)
  end

  def valid_identity?({:ip, value}) when is_tuple(value) and tuple_size(value) in [4, 8] do
    maximum = if tuple_size(value) == 4, do: 255, else: 65_535
    Enum.all?(Tuple.to_list(value), &(is_integer(&1) and &1 in 0..maximum))
  end

  def valid_identity?(_), do: false

  defp certificate_key(bytes) do
    if der?(bytes) do
      certificate(tbsCertificate: value) = :public_key.pkix_decode_cert(bytes, :otp)

      case public_key(value) do
        rsa_public(modulus: modulus, publicExponent: exponent) = public
        when is_integer(modulus) and modulus >= @minimum_modulus and is_integer(exponent) and
               exponent >= 3 ->
          {:ok, public}

        _ ->
          :error
      end
    else
      :error
    end
  rescue
    _ -> :error
  end

  defp public_key(tbs(subjectPublicKeyInfo: public_info(subjectPublicKey: key))), do: key
  defp public_key(_), do: nil

  defp strong_private?(
         rsa_private(
           version: :"two-prime",
           modulus: n,
           publicExponent: e,
           privateExponent: d,
           prime1: p,
           prime2: q,
           exponent1: dp,
           exponent2: dq,
           coefficient: coefficient,
           otherPrimeInfos: :asn1_NOVALUE
         )
       ) do
    Enum.all?([n, e, d, p, q, dp, dq, coefficient], &(is_integer(&1) and &1 > 0)) and
      n >= @minimum_modulus and e >= 3 and e < n and rem(e, 2) == 1 and d < n and
      p > 2 and q > 2 and coherent_factors?({n, e, d}, {p, q, dp, dq, coefficient})
  end

  defp strong_private?(_), do: false

  defp coherent_factors?({n, e, d}, {p, q, dp, dq, coefficient}) do
    p != q and p * q == n and
      rem(e * d, div((p - 1) * (q - 1), Integer.gcd(p - 1, q - 1))) == 1 and
      dp == rem(d, p - 1) and dq == rem(d, q - 1) and rem(q * coefficient, p) == 1
  end

  defp matching?(
         rsa_public(modulus: modulus, publicExponent: exponent),
         rsa_private(modulus: modulus, publicExponent: exponent)
       ),
       do: true

  defp matching?(_, _), do: false

  defp valid_crl?(bytes) do
    der?(bytes) and is_tuple(:public_key.der_decode(:CertificateList, bytes))
  rescue
    _ -> false
  end

  defp binaries([], _, []), do: :error
  defp binaries([], _, acc), do: {:ok, Enum.reverse(acc)}

  defp binaries([value | rest], left, acc) when left > 0 do
    if binary?(value), do: binaries(rest, left - 1, [value | acc]), else: :error
  end

  defp binaries(_, _, _), do: :error
  defp binary?(value), do: is_binary(value) and byte_size(value) in 1..65_536

  defp der?(<<48, length, body::binary>>) when length < 128, do: byte_size(body) == length

  defp der?(<<48, length, tail::binary>>) when length in 129..131 do
    count = length - 128

    case tail do
      <<encoded::binary-size(^count), body::binary>> ->
        :binary.first(encoded) != 0 and :binary.decode_unsigned(encoded) >= 128 and
          byte_size(body) == :binary.decode_unsigned(encoded)

      _ ->
        false
    end
  end

  defp der?(_), do: false
  defp failure, do: {:error, Error.new(:invalid_security, :pki)}
end
