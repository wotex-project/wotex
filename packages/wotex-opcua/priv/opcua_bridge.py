"""One bounded OPC UA exchange using asyncua 2.0.1; invoked explicitly by the BEAM owner."""
import asyncio
import base64
import ipaddress
import json
import logging
import math
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

from asyncua import Client, ua
from asyncua.crypto.security_policies import SecurityPolicyBasic256Sha256
from asyncua.crypto.validator import CertificateValidator, CertificateValidatorOptions
from cryptography import x509
from cryptography.hazmat.primitives.serialization import Encoding
from OpenSSL import crypto

logging.disable(logging.CRITICAL)
LIMIT = 131072


def certificate(path):
    data = Path(path).read_bytes()
    if len(data) > 65536:
        raise ValueError("certificate_limit")
    return x509.load_pem_x509_certificate(data) if data.startswith(b"-----") else x509.load_der_x509_certificate(data)


def verify_security(config):
    cert = certificate(config["server_certificate"])
    issuer = certificate(config["issuer_certificate"])
    cert.verify_directly_issued_by(issuer)
    issuer.verify_directly_issued_by(issuer)
    store = crypto.X509Store()
    for path in config["trust_certificates"]:
        store.add_cert(crypto.X509.from_cryptography(certificate(path)))
    crypto.X509StoreContext(store, crypto.X509.from_cryptography(cert),
                           [crypto.X509.from_cryptography(issuer)]).verify_certificate()
    crl_bytes = Path(config["crl"]).read_bytes()
    if len(crl_bytes) > 1048576:
        raise ValueError("crl_limit")
    crl = x509.load_pem_x509_crl(crl_bytes) if crl_bytes.startswith(b"-----") else x509.load_der_x509_crl(crl_bytes)
    now = datetime.now(timezone.utc)
    if (crl.issuer != issuer.subject or not crl.is_signature_valid(issuer.public_key())
            or crl.next_update_utc is None or not crl.last_update_utc <= now < crl.next_update_utc
            or crl.get_revoked_certificate_by_serial_number(cert.serial_number) is not None):
        raise ValueError("revocation_check_failed")
    san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    host = urlsplit(config["endpoint"]).hostname
    try:
        host_match = ipaddress.ip_address(host) in san.get_values_for_type(x509.IPAddress)
    except ValueError:
        host_match = host.lower() in [name.lower() for name in san.get_values_for_type(x509.DNSName)]
    if not host_match or config["server_uri"] not in san.get_values_for_type(x509.UniformResourceIdentifier):
        raise ValueError("endpoint_identity_mismatch")
    return cert


def variant(value):
    types = {name: getattr(ua.VariantType, name) for name in ["Boolean", "SByte", "Byte", "Int16", "UInt16",
             "Int32", "UInt32", "Int64", "UInt64", "Float", "Double", "String", "ByteString"]}
    kind, scalar = value["type"], value["value"]
    if kind == "ByteString" and scalar is not None:
        scalar = base64.b64decode(scalar, validate=True)
    if kind not in types or isinstance(scalar, (list, dict)):
        raise ValueError("unsupported_variant")
    if kind == "Boolean" and type(scalar) is not bool:
        raise ValueError("invalid_boolean")
    bounds = {"SByte": (-128, 127), "Byte": (0, 255), "Int16": (-32768, 32767), "UInt16": (0, 65535),
              "Int32": (-2**31, 2**31-1), "UInt32": (0, 2**32-1), "Int64": (-2**63, 2**63-1), "UInt64": (0, 2**64-1)}
    if kind in bounds and (type(scalar) is not int or not bounds[kind][0] <= scalar <= bounds[kind][1]):
        raise ValueError("invalid_integer")
    if kind in ["Float", "Double"] and type(scalar) not in [int, float]:
        raise ValueError("invalid_number")
    if kind in ["String", "ByteString"] and scalar is not None and not isinstance(scalar, (str, bytes)):
        raise ValueError("invalid_string")
    if kind in ["Float", "Double"] and (not math.isfinite(scalar) or
            (kind == "Float" and abs(scalar) > 3.4028234663852886e38)):
        raise ValueError("non_finite_number")
    return ua.Variant(scalar, types[kind])


def json_value(value, depth=0):
    if depth > 8:
        raise ValueError("value_depth")
    if isinstance(value, bytes):
        return {"type": "ByteString", "base64": base64.b64encode(value).decode("ascii")}
    if isinstance(value, list) and len(value) <= 1024:
        return [json_value(item, depth+1) for item in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    raise ValueError("unsupported_value")


async def exchange(config, message, timeout):
    pinned = verify_security(config)
    client = Client(config["endpoint"], timeout=timeout)
    client.application_uri = config["client_uri"]
    client.max_messagesize = 1048576
    client.max_chunkcount = 16
    validator = CertificateValidator(CertificateValidatorOptions.EXT_VALIDATION | CertificateValidatorOptions.PEER_SERVER)

    async def validate_peer(cert, description):
        if (cert.public_bytes(Encoding.DER) != pinned.public_bytes(Encoding.DER)
                or description.ApplicationUri != config["server_uri"]):
            raise ValueError("peer_identity_mismatch")
        await validator.validate(cert, description)

    client_validator = CertificateValidator(CertificateValidatorOptions.EXT_VALIDATION | CertificateValidatorOptions.PEER_CLIENT)
    await client_validator.validate(certificate(config["certificate"]), ua.ApplicationDescription(
        ApplicationUri=config["client_uri"], ApplicationType=ua.ApplicationType.Client))
    client.certificate_validator = validate_peer
    await client.set_security(SecurityPolicyBasic256Sha256, config["certificate"], config["private_key"],
                              server_certificate=config["server_certificate"], mode=ua.MessageSecurityMode.SignAndEncrypt)
    async with client:
        operation = message["type"]
        if operation == "probe":
            return "connected"
        node = client.get_node(message["node_id"])
        if operation == "read":
            data = await node.read_data_value(raise_on_bad_status=True)
            return {"type": data.Value.VariantType.name, "value": json_value(data.Value.Value),
                    "status": data.StatusCode.value}
        if operation == "write":
            await node.write_value(variant(message["value"]))
            return "written"
        if operation == "browse":
            children = await node.get_children()
            if len(children) > 256:
                raise ValueError("browse_limit")
            return [child.nodeid.to_string() for child in children]
        if operation == "call":
            args = message["value"]["arguments"]
            if len(args) > 32:
                raise ValueError("argument_limit")
            parent = client.get_node(message["value"]["object_id"])
            return json_value(await parent.call_method(node.nodeid, *[variant(arg) for arg in args]))
        raise ValueError("unsupported_operation")


async def owned_exchange(request, timeout):
    loop = asyncio.get_running_loop()
    task = asyncio.create_task(exchange(request["config"], request["message"], timeout))
    def owner_closed():
        os.read(sys.stdin.fileno(), 1)
        task.cancel()
    loop.add_reader(sys.stdin.fileno(), owner_closed)
    try:
        return await asyncio.wait_for(task, timeout)
    finally:
        loop.remove_reader(sys.stdin.fileno())


def main():
    request = None
    try:
        line = sys.stdin.buffer.readline(LIMIT + 1)
        if len(line) > LIMIT or not line.endswith(b"\n"):
            raise ValueError("request_limit")
        request = json.loads(line)
        timeout = request["timeout_ms"] / 1000
        if not 0 < timeout <= 60:
            raise ValueError("timeout_limit")
        value = asyncio.run(owned_exchange(request, timeout))
        response = {"id": request["id"], "ok": value}
        output = json.dumps(response, allow_nan=False, separators=(",", ":"))
        if len(output.encode()) >= LIMIT:
            raise ValueError("response_limit")
    except Exception:
        output = json.dumps({"id": request.get("id") if isinstance(request, dict) else None,
                             "error": "exchange_failed"})
    sys.stdout.write(output + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
