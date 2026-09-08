"""Generate disposable certificates and run an asyncua 2.0.1 secure loopback peer."""
import asyncio
import json
import logging
import socket
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from asyncua import Server, ua
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
    for role in ["server", "client", "expired", "wronghost"]:
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
                .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CLIENT_AUTH if role == "client" else ExtendedKeyUsageOID.SERVER_AUTH]), False)
                .add_extension(x509.SubjectAlternativeName(sans), False).sign(ca_key, hashes.SHA256()))
        (directory / (role+".der")).write_bytes(cert.public_bytes(serialization.Encoding.DER))
        key_path = directory / (role+".pem")
        key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        key_path.chmod(0o600)
        issued[role] = cert
    crl_builder = x509.CertificateRevocationListBuilder().issuer_name(name).last_update(now-timedelta(hours=1)).next_update(now+timedelta(days=1))
    (directory / "clean.crl").write_bytes(crl_builder.sign(ca_key, hashes.SHA256()).public_bytes(serialization.Encoding.DER))
    revoked = x509.RevokedCertificateBuilder().serial_number(issued["server"].serial_number).revocation_date(now-timedelta(minutes=1)).build()
    (directory / "revoked.crl").write_bytes(crl_builder.add_revoked_certificate(revoked).sign(ca_key, hashes.SHA256()).public_bytes(serialization.Encoding.DER))


async def main(directory):
    fixtures(directory)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    endpoint = f"opc.tcp://127.0.0.1:{port}/fixture/"
    server = Server()
    await server.init()
    server.set_endpoint(endpoint)
    await server.set_application_uri("urn:wotex:fixture:server")
    await server.load_certificate(directory / "server.der")
    await server.load_private_key(directory / "server.pem")
    server.set_security_policy([ua.SecurityPolicyType.Basic256Sha256_SignAndEncrypt])
    namespace = await server.register_namespace("urn:wotex:fixture")
    variable = await server.nodes.objects.add_variable(ua.NodeId("value", namespace), "Value", 21.5)
    await variable.set_writable()
    config = {"executable": sys.executable, "endpoint": endpoint, "certificate": str(directory / "client.der"),
              "private_key": str(directory / "client.pem"), "client_uri": "urn:wotex:fixture:client",
              "server_uri": "urn:wotex:fixture:server", "server_certificate": str(directory / "server.der"),
              "issuer_certificate": str(directory / "ca.der"), "trust_certificates": [str(directory / "ca.der")],
              "crl": str(directory / "clean.crl"), "node_id": variable.nodeid.to_string()}
    async with server:
        (directory / "config.json").write_text(json.dumps(config))
        print("secure peer ready", flush=True)
        await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main(Path(sys.argv[1]).resolve()))
