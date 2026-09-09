defmodule Wotex.CoAP.SecurityCallbacksTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP.Security.{CRLCache, Peer}
  require Record

  Record.defrecordp(
    :distribution_point,
    :DistributionPoint,
    Record.extract(:DistributionPoint, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :certificate_record,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :tbs_record,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  @fixtures Path.expand("../../fixtures/dtls_pki", __DIR__)

  test "WCO-S05 exact SAN and usage extend OTP validation without accepting an unknown extension" do
    server = certificate("server")
    identity = {:dns, "fixture.test"}
    assert Peer.verify(server, :valid_peer, identity) == {:valid, identity}
    assert Peer.verify(server, :valid, identity) == {:valid, identity}
    tbs = certificate_record(server, :tbsCertificate)

    no_extensions =
      certificate_record(server, tbsCertificate: tbs_record(tbs, extensions: :asn1_NOVALUE))

    assert Peer.verify(no_extensions, :valid_peer, identity) == {:fail, :invalid_peer_usage}
    assert Peer.verify(certificate("weak"), :valid_peer, identity) == {:fail, :weak_peer_key}
    assert Peer.verify(server, {:extension, :unknown_critical}, identity) == {:unknown, identity}

    assert Peer.verify(server, {:bad_cert, :unknown_ca}, identity) ==
             {:fail, :invalid_peer_certificate}

    assert Peer.verify(server, :invalid_event, identity) == {:fail, :invalid_peer_certificate}
    assert Peer.verify(certificate("weak"), :valid, identity) == {:fail, :weak_peer_key}

    assert Peer.verify(certificate("wrong-ku"), :valid_peer, identity) ==
             {:fail, :invalid_peer_usage}

    assert Peer.verify(certificate("wrong-eku"), :valid_peer, identity) ==
             {:fail, :invalid_peer_usage}

    assert Peer.verify(certificate("cn-only"), :valid_peer, identity) ==
             {:fail, :peer_identity_mismatch}

    assert Peer.verify(server, :valid_peer, {:ip, {127, 0, 0, 2}}) ==
             {:fail, :peer_identity_mismatch}

    assert Peer.verify(server, :valid_peer, {:ip, {0, 0, 0, 0, 0, 0, 0, 1}}) ==
             {:fail, :peer_identity_mismatch}

    assert Peer.verify(server, :valid_peer, :forged) == {:fail, :peer_identity_mismatch}
    assert Peer.verify(nil, :valid_peer, identity) == {:fail, :weak_peer_key}

    assert Peer.verify(certificate("wildcard"), :valid_peer, {:dns, "sensor.fixture.test"}) ==
             {:fail, :peer_identity_mismatch}
  end

  test "WCO-S05 CRL callbacks serve only the immutable supplied set and never dereference URLs" do
    crl = File.read!(Path.join(@fixtures, "valid-crl.der"))
    issuer = :public_key.pkix_crl_issuer(crl)
    cache = {:supplied, [crl]}

    point =
      distribution_point(
        distributionPoint: {:fullName, [{:uniformResourceIdentifier, ~c"http://127.0.0.1/crl"}]}
      )

    assert CRLCache.select(issuer, cache) == [crl]
    assert CRLCache.select([{:directoryName, issuer}, {:directoryName, issuer}], cache) == [crl]
    assert CRLCache.lookup(point, issuer, cache) == [crl]
    alternate = distribution_point(cRLIssuer: [{:directoryName, issuer}])
    assert CRLCache.lookup(alternate, :other_issuer, cache) == [crl]
    assert CRLCache.fresh_crl(point, crl) == crl
    assert CRLCache.lookup(point, issuer, {:supplied, []}) == :not_available
    assert CRLCache.select(issuer, {:supplied, ["invalid"]}) == []
    assert CRLCache.select([{:uniformResourceIdentifier, ~c"http://127.0.0.1/crl"}], cache) == []
    assert CRLCache.select(:unknown_issuer, cache) == []
    assert CRLCache.lookup(:invalid_point, issuer, cache) == :not_available
    assert CRLCache.select(issuer, :foreign_cache) == []

    for callback <- [lookup: 3, select: 2, fresh_crl: 2] do
      {name, arity} = callback
      assert function_exported?(CRLCache, name, arity)
    end
  end

  defp certificate(name),
    do: :public_key.pkix_decode_cert(File.read!(Path.join(@fixtures, name <> ".der")), :otp)
end
