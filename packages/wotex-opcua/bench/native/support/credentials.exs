defmodule Wotex.OPCUA.Bench.NativeCredentials do
  @moduledoc false

  # Disposable credentials for the same-stack peer, with the profile that
  # `priv/native/secure_peer.c` generates: one self-signed CA (RSA 2048,
  # certificate and CRL signing), a server and a client application certificate
  # issued by it (RSA 2048, SHA-256, the application URI, `localhost` and
  # 127.0.0.1 as subject alternative names, server or client authentication),
  # unencrypted PKCS#8 keys and an empty CRL. `write!/1` writes `ca.der`,
  # `server.der`, `server.key.der`, `client.der`, `client.key.der` and
  # `clean.crl` to a directory and returns their paths.

  require Record

  @hrl "public_key/include/public_key.hrl"

  Record.defrecordp(
    :tbs,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: @hrl)
  )

  Record.defrecordp(:extension, :Extension, Record.extract(:Extension, from_lib: @hrl))

  Record.defrecordp(
    :basic_constraints,
    :BasicConstraints,
    Record.extract(:BasicConstraints, from_lib: @hrl)
  )

  Record.defrecordp(:validity, :Validity, Record.extract(:Validity, from_lib: @hrl))

  Record.defrecordp(
    :attribute,
    :AttributeTypeAndValue,
    Record.extract(:AttributeTypeAndValue, from_lib: @hrl)
  )

  Record.defrecordp(
    :key_info,
    :OTPSubjectPublicKeyInfo,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: @hrl)
  )

  Record.defrecordp(
    :key_algorithm,
    :PublicKeyAlgorithm,
    Record.extract(:PublicKeyAlgorithm, from_lib: @hrl)
  )

  Record.defrecordp(
    :signature_algorithm,
    :SignatureAlgorithm,
    Record.extract(:SignatureAlgorithm, from_lib: @hrl)
  )

  Record.defrecordp(:rsa_public, :RSAPublicKey, Record.extract(:RSAPublicKey, from_lib: @hrl))
  Record.defrecordp(:rsa_private, :RSAPrivateKey, Record.extract(:RSAPrivateKey, from_lib: @hrl))
  Record.defrecordp(:tbs_crl, :TBSCertList, Record.extract(:TBSCertList, from_lib: @hrl))

  Record.defrecordp(
    :crl_signature,
    :TBSCertList_signature,
    Record.extract(:TBSCertList_signature, from_lib: @hrl)
  )

  Record.defrecordp(
    :crl_algorithm,
    :CertificateList_algorithmIdentifier,
    Record.extract(:CertificateList_algorithmIdentifier, from_lib: @hrl)
  )

  Record.defrecordp(:crl, :CertificateList, Record.extract(:CertificateList, from_lib: @hrl))

  @common_name {2, 5, 4, 3}
  @rsa_encryption {1, 2, 840, 113_549, 1, 1, 1}
  @sha256_with_rsa {1, 2, 840, 113_549, 1, 1, 11}
  @basic_constraints_id {2, 5, 29, 19}
  @key_usage_id {2, 5, 29, 15}
  @extended_key_usage_id {2, 5, 29, 37}
  @subject_alternative_name_id {2, 5, 29, 17}
  @server_authentication {1, 3, 6, 1, 5, 5, 7, 3, 1}
  @client_authentication {1, 3, 6, 1, 5, 5, 7, 3, 2}

  @spec write!(Path.t()) :: %{atom() => Path.t()}
  def write!(directory) do
    File.mkdir_p!(directory)
    now = DateTime.utc_now()
    ca_key = :public_key.generate_key({:rsa, 2048, 65_537})
    ca_name = name("Wotex fixture CA")

    ca =
      sign(ca_name, ca_name, ca_key, ca_key, 1, now, [
        extension(
          extnID: @basic_constraints_id,
          critical: true,
          extnValue: basic_constraints(cA: true, pathLenConstraint: 0)
        ),
        extension(
          extnID: @key_usage_id,
          critical: true,
          extnValue: [:digitalSignature, :keyCertSign, :cRLSign]
        )
      ])

    files = %{
      ca: write(directory, "ca.der", ca),
      crl: write(directory, "clean.crl", empty_crl(ca_name, ca_key, now))
    }

    [
      {:server, :server_key, "urn:wotex:fixture:server", @server_authentication, 2},
      {:client, :client_key, "urn:wotex:fixture:client", @client_authentication, 3}
    ]
    |> Enum.reduce(files, fn {role, key_role, uri, usage, serial}, files ->
      key = :public_key.generate_key({:rsa, 2048, 65_537})

      leaf =
        sign(
          name(Atom.to_string(role)),
          ca_name,
          key,
          ca_key,
          serial,
          now,
          leaf_extensions(uri, usage)
        )

      certificate = write(directory, "#{role}.der", leaf)

      private_key =
        write(directory, "#{role}.key.der", :public_key.der_encode(:PrivateKeyInfo, key))

      File.chmod!(private_key, 0o600)

      files
      |> Map.put(role, certificate)
      |> Map.put(key_role, private_key)
    end)
  end

  defp leaf_extensions(uri, usage) do
    [
      extension(
        extnID: @basic_constraints_id,
        critical: true,
        extnValue: basic_constraints(cA: false, pathLenConstraint: :asn1_NOVALUE)
      ),
      extension(
        extnID: @key_usage_id,
        critical: true,
        extnValue: [:digitalSignature, :nonRepudiation, :keyEncipherment, :dataEncipherment]
      ),
      extension(extnID: @extended_key_usage_id, critical: false, extnValue: [usage]),
      extension(
        extnID: @subject_alternative_name_id,
        critical: false,
        extnValue: [
          uniformResourceIdentifier: String.to_charlist(uri),
          dNSName: ~c"localhost",
          iPAddress: <<127, 0, 0, 1>>
        ]
      )
    ]
  end

  defp name(common_name),
    do: {:rdnSequence, [[attribute(type: @common_name, value: {:utf8String, common_name})]]}

  defp sign(subject, issuer, key, issuer_key, serial, now, extensions) do
    rsa_private(modulus: modulus, publicExponent: exponent) = key

    tbs(
      version: :v3,
      serialNumber: serial,
      signature: signature_algorithm(algorithm: @sha256_with_rsa, parameters: :asn1_NOVALUE),
      issuer: issuer,
      validity:
        validity(
          notBefore: time(DateTime.add(now, -1, :day)),
          notAfter: time(DateTime.add(now, 1, :day))
        ),
      subject: subject,
      subjectPublicKeyInfo:
        key_info(
          algorithm: key_algorithm(algorithm: @rsa_encryption, parameters: :asn1_NOVALUE),
          subjectPublicKey: rsa_public(modulus: modulus, publicExponent: exponent)
        ),
      issuerUniqueID: :asn1_NOVALUE,
      subjectUniqueID: :asn1_NOVALUE,
      extensions: extensions
    )
    |> :public_key.pkix_sign(issuer_key)
  end

  # The PKIX1Explicit-2009 form: open-type NULL parameters for SHA-256 with RSA.
  defp empty_crl(issuer, ca_key, now) do
    null = {:asn1_OPENTYPE, <<5, 0>>}

    list =
      tbs_crl(
        version: :v2,
        signature: crl_signature(algorithm: @sha256_with_rsa, parameters: null),
        issuer: issuer,
        thisUpdate: time(DateTime.add(now, -1, :hour)),
        nextUpdate: time(DateTime.add(now, 1, :day)),
        revokedCertificates: :asn1_NOVALUE,
        crlExtensions: :asn1_NOVALUE
      )

    signature = :public_key.sign(:public_key.der_encode(:TBSCertList, list), :sha256, ca_key)

    :public_key.der_encode(
      :CertificateList,
      crl(
        tbsCertList: list,
        signatureAlgorithm: crl_algorithm(algorithm: @sha256_with_rsa, parameters: null),
        signature: signature
      )
    )
  end

  defp time(%DateTime{} = time) do
    text = Calendar.strftime(time, "%y%m%d%H%M%SZ")
    {:utcTime, String.to_charlist(text)}
  end

  defp write(directory, name, bytes) do
    path = Path.join(directory, name)
    File.write!(path, bytes)
    path
  end
end
