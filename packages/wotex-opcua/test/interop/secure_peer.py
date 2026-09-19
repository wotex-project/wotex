"""Generate disposable certificates and run an asyncua 2.0.1 secure loopback peer.

Usage: secure_peer.py DIRECTORY [VARIANT]

The default variant generates credentials, offers the three SignAndEncrypt
policies and the anonymous, username and certificate user tokens. Other
variants reuse those credentials and write config-VARIANT.json:
expired_leaf and wrong_host present faulty server certificates, none_only
offers only Security None and anonymous_only offers only anonymous tokens.
The Resources method returns the peer's active subscription and MonitoredItem
counts as two UInt32 outputs. PublishFaults(withhold, discard) arms the peer to
answer the next `withhold` data-change Publish results with keepalives, keeping
each withheld message for Republish unless `discard` is true, and returns the
withheld and Republish counts. LoseSubscriptions queues a BadTimeout
StatusChangeNotification on every subscription and returns their count.
FailDeletes(count) makes the next `count` DeleteSubscriptions calls return
BadInternalError without deleting and returns the remaining count.
Slow(milliseconds) waits before returning its input, and the Variants variable
holds a Variant array that the native value profile does not support.
FailAcks(count) makes the next `count` Publish requests that acknowledge
notifications report BadInternalError for each acknowledgement and returns the
remaining count.
"""
import asyncio
import base64
import json
import logging
import socket
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from asyncua import Server, ua
from asyncua.common.methods import uamethod
from asyncua.crypto.permission_rules import User, UserRole
from asyncua.server.internal_session import InternalSession
from asyncua.server.internal_subscription import InternalSubscription
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

logging.disable(logging.CRITICAL)


def fixtures(directory):
    directory.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc)
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Wotex fixture CA")])
    ca = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(ca_key.public_key())
          .serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(days=1))
          .not_valid_after(now+timedelta(days=2)).add_extension(x509.BasicConstraints(ca=True, path_length=0), True)
          .add_extension(x509.KeyUsage(True, False, False, False, False, True, True, False, False), True)
          .sign(ca_key, hashes.SHA256()))
    (directory / "ca.der").write_bytes(ca.public_bytes(serialization.Encoding.DER))
    issued = {}
    for role in ["server", "client", "expired", "wronghost", "user", "stranger"]:
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        uri = "urn:wotex:fixture:" + ("client" if role == "client" else "server")
        import ipaddress
        sans = [x509.UniformResourceIdentifier(uri), x509.DNSName("localhost"),
                x509.IPAddress(ipaddress.ip_address("127.0.0.2" if role == "wronghost" else "127.0.0.1"))]
        cert = (x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, role)]))
                .issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(now-timedelta(days=2)).not_valid_after(now+timedelta(days=-1 if role == "expired" else 1))
                .add_extension(x509.BasicConstraints(ca=False, path_length=None), True)
                .add_extension(x509.KeyUsage(True, True, True, True, False, False, False, False, False), True)
                .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CLIENT_AUTH if role in ("client", "user", "stranger") else ExtendedKeyUsageOID.SERVER_AUTH]), False)
                .add_extension(x509.SubjectAlternativeName(sans), False).sign(ca_key, hashes.SHA256()))
        (directory / (role+".der")).write_bytes(cert.public_bytes(serialization.Encoding.DER))
        key_path = directory / (role+".pem")
        key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        key_path.chmod(0o600)
        der_key_path = directory / (role + ".key.der")
        der_key_path.write_bytes(key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        der_key_path.chmod(0o600)
        issued[role] = cert
    crl_builder = x509.CertificateRevocationListBuilder().issuer_name(name).last_update(now-timedelta(hours=1)).next_update(now+timedelta(days=1))
    (directory / "clean.crl").write_bytes(crl_builder.sign(ca_key, hashes.SHA256()).public_bytes(serialization.Encoding.DER))
    revoked = x509.RevokedCertificateBuilder().serial_number(issued["server"].serial_number).revocation_date(now-timedelta(minutes=1)).build()
    (directory / "revoked.crl").write_bytes(crl_builder.add_revoked_certificate(revoked).sign(ca_key, hashes.SHA256()).public_bytes(serialization.Encoding.DER))
    stale = (x509.CertificateRevocationListBuilder().issuer_name(name).last_update(now-timedelta(days=2))
             .next_update(now-timedelta(days=1)))
    (directory / "expired.crl").write_bytes(stale.sign(ca_key, hashes.SHA256()).public_bytes(serialization.Encoding.DER))
    other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    other_path = directory / "other.key.der"
    other_path.write_bytes(other_key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    other_path.chmod(0o600)
    other_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Untrusted fixture CA")])
    other_ca = (x509.CertificateBuilder().subject_name(other_name).issuer_name(other_name)
                .public_key(other_key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=2))
                .add_extension(x509.BasicConstraints(ca=True, path_length=0), True)
                .add_extension(x509.KeyUsage(True, False, False, False, False, True, True, False, False), True)
                .sign(other_key, hashes.SHA256()))
    (directory / "other-ca.der").write_bytes(other_ca.public_bytes(serialization.Encoding.DER))


USERNAME = "operator"
PASSWORD = "correct horse"


class FixtureUsers:
    """Admits anonymous users, one password and one user certificate.

    asyncua passes the channel's application certificate for anonymous and
    username tokens and the verified token certificate for X509 tokens.
    """

    def __init__(self, application, certificate):
        self.application = application
        self.certificate = certificate

    def get_user(self, iserver, username=None, password=None, certificate=None):
        if username is not None:
            if username == USERNAME and password == PASSWORD:
                return User(role=UserRole.User, name=USERNAME)
            return None
        if certificate == self.certificate:
            return User(role=UserRole.User, name="certificate")
        if certificate is None or certificate == self.application:
            return User(role=UserRole.User)
        return None


POLICIES = [ua.SecurityPolicyType.Basic256Sha256_SignAndEncrypt,
            ua.SecurityPolicyType.Aes128Sha256RsaOaep_SignAndEncrypt,
            ua.SecurityPolicyType.Aes256Sha256RsaPss_SignAndEncrypt]


async def main(directory, variant):
    if variant == "default":
        fixtures(directory)
    elif variant not in ("expired_leaf", "wrong_host", "none_only", "anonymous_only", "encrypted_tokens"):
        raise SystemExit("unknown variant")
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    endpoint = f"opc.tcp://127.0.0.1:{port}/fixture/"
    users = FixtureUsers((directory / "client.der").read_bytes(), (directory / "user.der").read_bytes())
    server = Server(user_manager=users)
    await server.init()
    server.set_endpoint(endpoint)
    await server.set_application_uri("urn:wotex:fixture:server")
    leaf = {"expired_leaf": "expired", "wrong_host": "wronghost"}.get(variant, "server")
    await server.load_certificate(directory / (leaf + ".der"))
    await server.load_private_key(directory / (leaf + ".pem"))
    if variant == "none_only":
        server.set_security_policy([ua.SecurityPolicyType.NoSecurity])
    else:
        server.set_security_policy(POLICIES)
    if variant == "anonymous_only":
        server.set_identity_tokens([ua.AnonymousIdentityToken])
    else:
        server.set_identity_tokens([ua.AnonymousIdentityToken, ua.UserNameIdentityToken, ua.X509IdentityToken])
    namespace = await server.register_namespace("urn:wotex:fixture")
    variable = await server.nodes.objects.add_variable(ua.NodeId("value", namespace), "Value", 21.5)
    await variable.set_writable()
    byte_values = await server.nodes.objects.add_variable(ua.NodeId("byte_values", namespace),
                                                          "ByteValues", [b"a", b"b"],
                                                          ua.VariantType.ByteString)
    await byte_values.set_writable()
    byte_value = await server.nodes.objects.add_variable(ua.NodeId("byte_value", namespace),
                                                         "ByteValue", b"seed",
                                                         ua.VariantType.ByteString)
    await byte_value.set_writable()
    int_values = await server.nodes.objects.add_variable(ua.NodeId("int_values", namespace),
                                                         "IntValues", [-2147483648, 0, 7],
                                                         ua.VariantType.Int32)
    await int_values.set_writable()
    double_values = await server.nodes.objects.add_variable(ua.NodeId("double_values", namespace),
                                                            "DoubleValues", [1.5, -0.0],
                                                            ua.VariantType.Double)
    await double_values.set_writable()
    node_value = await server.nodes.objects.add_variable(ua.NodeId("node_value", namespace),
                                                         "NodeValue", ua.NodeId("value", namespace),
                                                         ua.VariantType.NodeId)
    await node_value.set_writable()
    name_value = await server.nodes.objects.add_variable(ua.NodeId("name_value", namespace),
                                                         "NameValue", ua.QualifiedName("Name", namespace),
                                                         ua.VariantType.QualifiedName)
    await name_value.set_writable()

    @uamethod
    def add_values(parent, left, right):
        return left + right

    method = await server.nodes.objects.add_method(ua.NodeId("add", namespace), "Add",
                                                     add_values,
                                                     [ua.VariantType.Double, ua.VariantType.Double],
                                                     [ua.VariantType.Double])
    variants = await server.nodes.objects.add_variable(ua.NodeId("variants", namespace), "Variants",
                                                       [ua.Variant(1, ua.VariantType.Int32),
                                                        ua.Variant("x", ua.VariantType.String)],
                                                       ua.VariantType.Variant,
                                                       ua.NodeId(ua.ObjectIds.BaseDataType))

    @uamethod
    async def slow(parent, milliseconds):
        await asyncio.sleep(milliseconds / 1000)
        return ua.Variant(milliseconds, ua.VariantType.UInt32)

    slow_method = await server.nodes.objects.add_method(ua.NodeId("slow", namespace), "Slow", slow,
                                                        [ua.VariantType.UInt32], [ua.VariantType.UInt32])
    service = server.iserver.subscription_service
    faults = {"withhold": 0, "discard": False, "withheld": 0, "republished": 0, "fail_deletes": 0, "fail_acks": 0}
    delete_subscriptions = InternalSession.delete_subscriptions

    async def failing_delete(session, ids):
        if not faults["fail_deletes"]:
            return await delete_subscriptions(session, ids)
        faults["fail_deletes"] -= 1
        return [ua.StatusCode(ua.StatusCodes.BadInternalError) for _ in ids]

    InternalSession.delete_subscriptions = failing_delete
    publish_acks = InternalSession.publish

    def failing_publish(session, acks=None):
        count, results = publish_acks(session, acks)
        if faults["fail_acks"] and results:
            faults["fail_acks"] -= 1
            results = [ua.StatusCode(ua.StatusCodes.BadInternalError) for _ in results]
        return count, results

    InternalSession.publish = failing_publish
    pop_result = InternalSubscription._pop_publish_result
    republish_result = InternalSubscription.republish

    def withheld_result(subscription):
        result = pop_result(subscription)
        message = result.NotificationMessage
        if not (faults["withhold"] and message.NotificationData and subscription.pub_request_callback):
            return result
        faults["withhold"] -= 1
        faults["withheld"] += 1
        if faults["discard"]:
            subscription._not_acknowledged_results.pop(message.SequenceNumber, None)
        keepalive = ua.PublishResult()
        keepalive.SubscriptionId = result.SubscriptionId
        keepalive.NotificationMessage.SequenceNumber = subscription._notification_seq
        keepalive.NotificationMessage.PublishTime = message.PublishTime
        keepalive.AvailableSequenceNumbers = list(subscription._not_acknowledged_results.keys())
        return keepalive

    def counted_republish(subscription, sequence):
        faults["republished"] += 1
        return republish_result(subscription, sequence)

    InternalSubscription._pop_publish_result = withheld_result
    InternalSubscription.republish = counted_republish

    @uamethod
    def publish_faults(parent, withhold, discard):
        if withhold:
            faults["withhold"] = withhold
            faults["discard"] = discard
        return (ua.Variant(faults["withheld"], ua.VariantType.UInt32),
                ua.Variant(faults["republished"], ua.VariantType.UInt32))

    @uamethod
    async def lose_subscriptions(parent):
        subscriptions = list(service.subscriptions.values())
        for entry in subscriptions:
            await entry.monitored_item_srv.trigger_statuschange(ua.StatusCode(ua.StatusCodes.BadTimeout))
        return ua.Variant(len(subscriptions), ua.VariantType.UInt32)

    @uamethod
    def fail_deletes(parent, count):
        faults["fail_deletes"] = count
        return ua.Variant(faults["fail_deletes"], ua.VariantType.UInt32)

    @uamethod
    def fail_acks(parent, count):
        faults["fail_acks"] = count
        return ua.Variant(faults["fail_acks"], ua.VariantType.UInt32)

    acks_method = await server.nodes.objects.add_method(ua.NodeId("fail_acks", namespace),
                                                        "FailAcks", fail_acks,
                                                        [ua.VariantType.UInt32], [ua.VariantType.UInt32])
    delete_method = await server.nodes.objects.add_method(ua.NodeId("fail_deletes", namespace),
                                                          "FailDeletes", fail_deletes,
                                                          [ua.VariantType.UInt32], [ua.VariantType.UInt32])
    faults_method = await server.nodes.objects.add_method(ua.NodeId("publish_faults", namespace),
                                                          "PublishFaults", publish_faults,
                                                          [ua.VariantType.UInt32, ua.VariantType.Boolean],
                                                          [ua.VariantType.UInt32, ua.VariantType.UInt32])
    loss_method = await server.nodes.objects.add_method(ua.NodeId("lose_subscriptions", namespace),
                                                        "LoseSubscriptions", lose_subscriptions, [],
                                                        [ua.VariantType.UInt32])

    @uamethod
    def resources(parent):
        subscriptions = list(service.subscriptions.values())
        items = sum(len(entry.monitored_item_srv._monitored_items) for entry in subscriptions)
        return (ua.Variant(len(subscriptions), ua.VariantType.UInt32),
                ua.Variant(items, ua.VariantType.UInt32))

    resources_method = await server.nodes.objects.add_method(ua.NodeId("resources", namespace),
                                                             "Resources", resources, [],
                                                             [ua.VariantType.UInt32, ua.VariantType.UInt32])

    # Records the EncryptionAlgorithm of every UserName token the server
    # decrypts; asyncua itself accepts any algorithm it can decrypt.
    token_algorithms = []
    decrypt_user_token = server.iserver.decrypt_user_token

    def record_user_token(isession, token):
        token_algorithms.append(token.EncryptionAlgorithm or "")
        return decrypt_user_token(isession, token)

    server.iserver.decrypt_user_token = record_user_token

    @uamethod
    def token_algorithm(parent):
        return ua.Variant(token_algorithms[-1] if token_algorithms else "", ua.VariantType.String)

    token_method = await server.nodes.objects.add_method(ua.NodeId("token_algorithm", namespace),
                                                         "TokenAlgorithm", token_algorithm, [],
                                                         [ua.VariantType.String])
    config = {"executable": sys.executable, "endpoint": endpoint, "certificate": str(directory / "client.der"),
              "private_key": str(directory / "client.pem"), "client_uri": "urn:wotex:fixture:client",
              "server_uri": "urn:wotex:fixture:server", "server_certificate": str(directory / "server.der"),
              "issuer_certificate": str(directory / "ca.der"), "trust_certificates": [str(directory / "ca.der")],
              "crl": str(directory / "clean.crl"), "node_id": variable.nodeid.to_string(),
              "byte_array_node_id": byte_values.nodeid.to_string(),
              "byte_node_id": byte_value.nodeid.to_string(),
              "int_array_node_id": int_values.nodeid.to_string(),
              "double_array_node_id": double_values.nodeid.to_string(),
              "node_value_id": node_value.nodeid.to_string(),
              "name_value_id": name_value.nodeid.to_string(),
              "object_id": "ns=0;i=85", "method_id": method.nodeid.to_string(),
              "resources_method_id": resources_method.nodeid.to_string(),
              "faults_method_id": faults_method.nodeid.to_string(),
              "loss_method_id": loss_method.nodeid.to_string(),
              "delete_method_id": delete_method.nodeid.to_string(),
              "acks_method_id": acks_method.nodeid.to_string(),
              "variants_node_id": variants.nodeid.to_string(),
              "slow_method_id": slow_method.nodeid.to_string(),
              "token_method_id": token_method.nodeid.to_string(),
              "username": USERNAME, "password": PASSWORD, "variant": variant}
    def envelope(path):
        return {"type": "bytes", "base64": base64.b64encode((directory / path).read_bytes()).decode("ascii")}
    native_open = {"endpoint": endpoint,
                   "security_policy": "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",
                   "security_mode": "SignAndEncrypt", "client_uri": "urn:wotex:fixture:client",
                   "server_uri": "urn:wotex:fixture:server", "certificate": envelope("client.der"),
                   "private_key": envelope("client.key.der"), "server_certificate": envelope("server.der"),
                   "trust_certificate": envelope("ca.der"), "crl": envelope("clean.crl"),
                   "authentication": {"type": "anonymous"}, "session_timeout_ms": 60000}
    async with server:
        if variant == "encrypted_tokens":
            # asyncua advertises the UserName token policy as None on
            # SignAndEncrypt endpoints; this variant names each endpoint's own
            # policy, so a client must encrypt the password as that policy requires.
            for description in server.iserver.endpoints:
                for policy in description.UserIdentityTokens:
                    if policy.TokenType == ua.UserTokenType.UserName:
                        policy.SecurityPolicyUri = description.SecurityPolicyUri
        if variant == "default":
            (directory / "config.json").write_text(json.dumps(config))
            (directory / "native-open.json").write_text(json.dumps(native_open) + "\n")
        else:
            (directory / f"config-{variant}.json").write_text(json.dumps(config))
        print("secure peer ready", flush=True)
        await asyncio.Event().wait()


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    asyncio.run(main(Path(sys.argv[1]).resolve(), sys.argv[2] if len(sys.argv) == 3 else "default"))
