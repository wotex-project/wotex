"""Generate disposable certificates and run an asyncua 2.0.1 secure loopback peer.

Usage: secure_peer.py DIRECTORY [VARIANT]

The default variant generates credentials, offers the three SignAndEncrypt
policies and the anonymous, username and certificate user tokens. Other
variants reuse those credentials and write config-VARIANT.json:
expired_leaf and wrong_host present faulty server certificates, none_only
offers only Security None and anonymous_only offers only anonymous tokens.
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
    elif variant not in ("expired_leaf", "wrong_host", "none_only", "anonymous_only"):
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
    config = {"executable": sys.executable, "endpoint": endpoint, "certificate": str(directory / "client.der"),
              "private_key": str(directory / "client.pem"), "client_uri": "urn:wotex:fixture:client",
              "server_uri": "urn:wotex:fixture:server", "server_certificate": str(directory / "server.der"),
              "issuer_certificate": str(directory / "ca.der"), "trust_certificates": [str(directory / "ca.der")],
              "crl": str(directory / "clean.crl"), "node_id": variable.nodeid.to_string(),
              "byte_array_node_id": byte_values.nodeid.to_string(),
              "byte_node_id": byte_value.nodeid.to_string(),
              "node_value_id": node_value.nodeid.to_string(),
              "name_value_id": name_value.nodeid.to_string(),
              "object_id": "ns=0;i=85", "method_id": method.nodeid.to_string(),
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
