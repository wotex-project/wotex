"""WTH-C07/WTH-N03: source archive and disposable native workspace boundaries."""
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2] / "priv/openthread/build.py"
spec = importlib.util.spec_from_file_location("native_build", SOURCE)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class BuildBoundary(unittest.TestCase):
    def test_WTH_N03_pins_name_exact_crypto_override(self):
        pins = json.loads((SOURCE.parent / "dependencies.json").read_text())
        self.assertEqual(pins["sources"]["mbedtls"]["commit"], "068ff080b369adfac81509f9b57b2afabaf82dc5")
        self.assertTrue(all(len(pin["archive_sha256"]) == 64 for pin in pins["sources"].values()))

    def archive(self, name, kind=tarfile.REGTYPE):
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w") as stream:
            member = tarfile.TarInfo(name)
            member.type = kind
            member.linkname = "/outside"
            member.mode = 0o7777
            if kind == tarfile.REGTYPE:
                member.size = 4
                stream.addfile(member, io.BytesIO(b"data"))
            else:
                stream.addfile(member)
        buffer.seek(0)
        return tarfile.open(fileobj=buffer)

    def test_WTH_N03_archive_escape_and_links_fail_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, kind in (("../escape", tarfile.REGTYPE), ("/absolute", tarfile.REGTYPE),
                               ("root/../escape", tarfile.REGTYPE), ("different/file", tarfile.REGTYPE),
                               ("root/link", tarfile.SYMTYPE), ("root/link", tarfile.LNKTYPE),
                               ("root/device", tarfile.CHRTYPE), ("root/fifo", tarfile.FIFOTYPE)):
                with self.archive(name, kind) as archive, self.assertRaises(ValueError):
                    native.extract(archive, root, "root")
                self.assertEqual(list(root.iterdir()), [])

    def test_WTH_N03_archive_preserves_bytes_and_execute_without_special_mode_bits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.archive("root/run") as archive:
                native.extract(archive, root, "root")
            file = root / "root/run"
            self.assertEqual(file.read_bytes(), b"data")
            self.assertEqual(file.stat().st_mode & 0o7777, 0o755)
            original = native.tree_digest(root)
            file.write_bytes(b"changed")
            self.assertNotEqual(native.tree_digest(root), original)

    def test_WTH_N03_cached_download_hash_mismatch_fails_without_network(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "archive"
            file.write_bytes(b"wrong")
            with self.assertRaises(ValueError):
                native.download("https://invalid.invalid/unused", file, "0" * 64)
            self.assertEqual(file.read_bytes(), b"wrong")


if __name__ == "__main__":
    unittest.main(verbosity=2)
