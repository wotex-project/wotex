#!/usr/bin/env python3
"""Generate public test-only RSA certificates and CRLs; none are production credentials."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def generate(openssl, output):
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="wotex-coap-pki-") as directory:
        work = Path(directory)
        def run(*args):
            subprocess.run([openssl, *map(str, args)], cwd=work, check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        def key(name, bits=2048):
            run("genrsa", "-out", name + ".key", bits)
        key("root")
        run("req", "-new", "-x509", "-key", "root.key", "-out", "root.pem", "-days", "36500",
            "-subj", "/CN=Wotex Public Test Root", "-addext", "basicConstraints=critical,CA:TRUE",
            "-addext", "keyUsage=critical,keyCertSign,cRLSign")
        (work / "index").write_text("")
        (work / "serial").write_text("1000\n")
        (work / "crlnumber").write_text("1000\n")
        (work / "newcerts").mkdir()
        base = """[ca]
default_ca=authority
[authority]
database=index
new_certs_dir=newcerts
certificate=root.pem
private_key=root.key
serial=serial
crlnumber=crlnumber
default_md=sha256
default_crl_days=36500
policy=names
unique_subject=no
[names]
commonName=supplied
[extensions]
basicConstraints=critical,CA:FALSE
"""
        for name, san, ku, eku, extra in [
            ("client", "DNS:client.fixture.test", "digitalSignature", "clientAuth", ""),
            ("server", "DNS:fixture.test,IP:127.0.0.1", "digitalSignature", "serverAuth", ""),
            ("wrong-san", "DNS:wrong.test", "digitalSignature", "serverAuth", ""),
            ("expired", "DNS:fixture.test", "digitalSignature", "serverAuth", ""),
            ("revoked", "DNS:fixture.test", "digitalSignature", "serverAuth", ""),
            ("wrong-ku", "DNS:fixture.test", "keyEncipherment", "serverAuth", ""),
            ("wrong-eku", "DNS:fixture.test", "digitalSignature", "clientAuth", ""),
            ("critical", "DNS:fixture.test", "digitalSignature", "serverAuth", "1.2.3.4=critical,DER:01:01:FF\n"),
            ("cn-only", None, "digitalSignature", "serverAuth", ""),
            ("wildcard", "DNS:*.fixture.test", "digitalSignature", "serverAuth", ""),
            ("weak", "DNS:fixture.test", "digitalSignature", "serverAuth", ""),
        ]:
            key(name, 1024 if name == "weak" else 2048)
            configuration = base + f"keyUsage=critical,{ku}\nextendedKeyUsage={eku}\n" + extra
            if san:
                configuration += f"subjectAltName={san}\n"
            (work / "ca.cnf").write_text(configuration)
            run("req", "-new", "-key", name + ".key", "-out", name + ".csr", "-subj", "/CN=fixture.test")
            run("ca", "-batch", "-config", "ca.cnf", "-extensions", "extensions", "-notext",
                "-in", name + ".csr", "-out", name + ".pem", "-startdate", "20200101000000Z" if name != "expired" else "20000101000000Z",
                "-enddate", "20991231235959Z" if name != "expired" else "20010101000000Z")
            run("x509", "-in", name + ".pem", "-outform", "DER", "-out", output / (name + ".der"))
            run("rsa", "-in", name + ".key", "-traditional", "-outform", "DER", "-out", output / (name + "-key.der"))
        run("pkcs8", "-topk8", "-nocrypt", "-in", "client.key", "-outform", "DER", "-out", output / "client-pkcs8.der")
        run("x509", "-in", "root.pem", "-outform", "DER", "-out", output / "root.der")
        run("ca", "-gencrl", "-config", "ca.cnf", "-out", "valid.crl", "-crl_lastupdate", "20200101000000Z", "-crl_nextupdate", "20991231235959Z")
        run("crl", "-in", "valid.crl", "-outform", "DER", "-out", output / "valid-crl.der")
        run("ca", "-revoke", "revoked.pem", "-config", "ca.cnf")
        run("ca", "-gencrl", "-config", "ca.cnf", "-out", "revoked.crl", "-crl_lastupdate", "20200101000000Z", "-crl_nextupdate", "20991231235959Z")
        run("crl", "-in", "revoked.crl", "-outform", "DER", "-out", output / "revoked-crl.der")
    manifest = {"schema": "wotex-coap-public-pki-fixtures-v1", "purpose": "public test-only credentials",
                "openssl": subprocess.check_output([openssl, "version", "-a"], text=True),
                "files": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.glob("*.der"))}}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--openssl", default="openssl")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    generate(args.openssl, args.output.resolve())
