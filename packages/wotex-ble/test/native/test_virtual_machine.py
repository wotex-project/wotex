"""WBL-V11/C09: the explicit virtual lane rejects missing or changed evidence."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "wotex_ble_virtual_machine",
    Path(__file__).resolve().parents[1] / "interop/virtual_machine.py",
)
VM = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VM)


class VirtualMachineBoundaryTest(unittest.TestCase):
    def test_WBL_V11_unrelated_workspace_is_preserved(self):
        with tempfile.TemporaryDirectory(prefix="wbl-unrelated-") as temporary:
            directory = Path(temporary)
            existing = directory / "owned-by-caller.txt"
            existing.write_text("preserve")
            with self.assertRaisesRegex(ValueError, "unrelated nonempty"):
                with VM.owned_workspace(directory, {"native": "one"}):
                    self.fail("Unrelated workspace was admitted")
            self.assertEqual(existing.read_text(), "preserve")
            self.assertEqual(list(directory.iterdir()), [existing])

    def test_WBL_V11_requires_absolute_external_directory_and_exact_arguments(self):
        for value in ("relative", str(VM.SOURCE), str(VM.SOURCE / "fixture")):
            with self.assertRaises(ValueError):
                VM.workspace(value)
        for arguments in (
            [],
            ["build"],
            ["wrong", "/tmp/example"],
            ["build", "/tmp/example", "extra"],
        ):
            with self.assertRaises(ValueError):
                VM.main(arguments)
        with tempfile.TemporaryDirectory(prefix="wbl-link-") as temporary:
            directory = Path(temporary)
            link = directory / "link"
            link.symlink_to(directory, target_is_directory=True)
            with self.assertRaises(ValueError):
                VM.workspace(str(link))

    def test_WBL_V11_manifest_mismatch_cannot_reuse_another_build(self):
        with tempfile.TemporaryDirectory(prefix="wbl-manifest-") as temporary:
            directory = Path(temporary)
            with VM.owned_workspace(directory, {"native": "one"}) as manifest:
                self.assertEqual(manifest["phase"], "building")
            original = (directory / "manifest.json").read_bytes()
            with self.assertRaisesRegex(ValueError, "does not match"):
                with VM.owned_workspace(directory, {"native": "two"}):
                    self.fail("Changed source manifest was admitted")
            self.assertEqual((directory / "manifest.json").read_bytes(), original)
            with self.assertRaisesRegex(ValueError, "incomplete"):
                VM.verify(directory, json.loads(original))

    def test_WBL_V11_corrupted_or_symlinked_artifact_fails_before_docker(self):
        with tempfile.TemporaryDirectory(prefix="wbl-integrity-") as temporary:
            directory = Path(temporary)
            artifact = directory / "rootfs.raw"
            artifact.write_bytes(b"original fixture")
            manifest = {
                "phase": "ready",
                "artifacts": {
                    "rootfs.raw": VM.digest(artifact),
                    "context/bluez.tar.gz": "absent",
                    "rootfs.tar": "absent",
                    "native-build.json": "absent",
                },
            }
            artifact.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "artifact differs"):
                VM.verify(directory, manifest)
            artifact.unlink()
            with self.assertRaisesRegex(ValueError, "artifact differs"):
                VM.verify(directory, manifest)
            other = directory / "other.raw"
            other.write_bytes(b"original fixture")
            artifact.symlink_to(other)
            with self.assertRaisesRegex(ValueError, "artifact differs"):
                VM.verify(directory, manifest)

    def test_WBL_C03_two_runners_cannot_mutate_the_same_workspace(self):
        with tempfile.TemporaryDirectory(prefix="wbl-lock-") as temporary:
            directory = Path(temporary)
            with VM.owned_workspace(directory, {}) as first:
                with self.assertRaises(BlockingIOError):
                    with VM.owned_workspace(directory, {}):
                        self.fail("Concurrent ownership was admitted")
            with VM.owned_workspace(directory, {}) as second:
                self.assertEqual(first, second)
