"""WBL-N03/C09: public fixture ownership and immutable build inputs."""

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

INTEROP = Path(__file__).resolve().parents[1] / "interop"
NATIVE_SPEC = importlib.util.spec_from_file_location(
    "virtual_machine", INTEROP / "virtual_machine.py"
)
NATIVE = importlib.util.module_from_spec(NATIVE_SPEC)
NATIVE_SPEC.loader.exec_module(NATIVE)
SPEC = importlib.util.spec_from_file_location(
    "wotex_ble_public_machine", INTEROP / "public_machine.py"
)
PUBLIC = importlib.util.module_from_spec(SPEC)
with mock.patch.dict(sys.modules, {"virtual_machine": NATIVE}):
    SPEC.loader.exec_module(PUBLIC)


class PublicMachineBoundaryTest(unittest.TestCase):
    def test_WBL_N03_unrelated_or_changed_workspace_is_never_reused(self):
        with tempfile.TemporaryDirectory(prefix="wbl-public-manifest-") as temporary:
            root = Path(temporary)
            with PUBLIC.owned(root, {"package": "source-one"}) as manifest:
                self.assertEqual(manifest["phase"], "building")
                with self.assertRaises(BlockingIOError):
                    with PUBLIC.owned(root, {"package": "source-one"}):
                        self.fail("Concurrent ownership was accepted")
            original = (root / "manifest.json").read_bytes()
            with self.assertRaisesRegex(ValueError, "does not match"):
                with PUBLIC.owned(root, {"package": "source-two"}):
                    self.fail("Changed source was accepted")
            self.assertEqual((root / "manifest.json").read_bytes(), original)
        with tempfile.TemporaryDirectory(prefix="wbl-public-unrelated-") as temporary:
            root = Path(temporary)
            original = root / "consumer.txt"
            original.write_text("preserve")
            with self.assertRaisesRegex(ValueError, "unrelated"):
                with PUBLIC.owned(root, {}):
                    self.fail("Unrelated workspace was accepted")
            self.assertEqual(original.read_text(), "preserve")

    def test_WBL_N03_build_tools_require_the_exact_source_hash_before_reuse(self):
        with tempfile.TemporaryDirectory(prefix="wbl-public-tools-") as temporary:
            root = Path(temporary)
            archive = root / "source.tar.gz"
            archive.write_bytes(b"pinned-source")
            expected = NATIVE.digest(archive)
            with mock.patch.object(PUBLIC.urllib.request, "urlopen") as network:
                PUBLIC.fetch(archive, "https://example.invalid/source", expected)
                network.assert_not_called()
                archive.write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "differs"):
                    PUBLIC.fetch(archive, "https://example.invalid/source", expected)
                network.assert_not_called()

    def test_WBL_N03_partial_or_tampered_image_fails_before_docker(self):
        with tempfile.TemporaryDirectory(prefix="wbl-public-image-") as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(ValueError, "incomplete"):
                PUBLIC.verify(root, {"phase": "building"})
            artifact = root / "rootfs.raw"
            artifact.write_bytes(b"original")
            manifest = {
                "phase": "ready",
                "artifacts": {
                    "rootfs.raw": NATIVE.digest(artifact),
                    **{name: "absent" for name in PUBLIC.ARTIFACTS - {"rootfs.raw"}},
                },
            }
            artifact.write_bytes(b"changed")
            with mock.patch.object(NATIVE, "output") as docker:
                with self.assertRaisesRegex(ValueError, "artifact differs"):
                    PUBLIC.verify(root, manifest)
                docker.assert_not_called()

    def test_WBL_N03_source_manifest_requires_real_sibling_packages(self):
        with tempfile.TemporaryDirectory(prefix="wbl-public-source-") as temporary:
            root = Path(temporary)
            with mock.patch.object(NATIVE, "SOURCE", root / "wotex-ble"):
                with self.assertRaisesRegex(ValueError, "sibling package"):
                    PUBLIC.sources()
                for package in PUBLIC.PACKAGES:
                    directory = root / package
                    directory.mkdir()
                    (directory / "mix.exs").write_text("project")
                    (directory / "mix.lock").write_text("%{}")
                manifest = PUBLIC.sources()
                self.assertEqual(len(manifest), 6)
                source = root / "wotex-ble/lib"
                source.mkdir()
                (source / "escaped.ex").symlink_to(root / "wotex/mix.exs")
                with self.assertRaisesRegex(ValueError, "regular owned"):
                    PUBLIC.sources()

    def test_WBL_N03_native_alias_survives_reuse_and_rejects_identity_changes(self):
        with tempfile.TemporaryDirectory(prefix="wbl-public-alias-") as temporary:
            root = Path(temporary)
            manifest = {"phase": "building"}
            identifier = "sha256:" + "a" * 64
            with (
                mock.patch.object(NATIVE, "run") as docker,
                mock.patch.object(NATIVE, "output", return_value=identifier),
            ):
                alias = PUBLIC.preserve_base_alias(root, manifest, identifier)
                self.assertRegex(alias, r"^wotex-ble-owned-native-base:[0-9a-f]{32}$")
                docker.assert_called_once_with("docker", "tag", identifier, alias)
                docker.reset_mock()
                self.assertEqual(PUBLIC.preserve_base_alias(root, manifest, identifier), alias)
                docker.assert_not_called()
            with (
                mock.patch.object(NATIVE, "run") as docker,
                mock.patch.object(NATIVE, "output", return_value="sha256:" + "b" * 64),
            ):
                with self.assertRaisesRegex(ValueError, "changed identity"):
                    PUBLIC.preserve_base_alias(root, manifest, identifier)
                docker.assert_not_called()
            manifest["native_base_alias"] = "unrelated:latest"
            with mock.patch.object(NATIVE, "output") as docker:
                with self.assertRaisesRegex(ValueError, "changed identity"):
                    PUBLIC.preserve_base_alias(root, manifest, identifier)
                docker.assert_not_called()

    def test_WBL_N03_argument_errors_do_not_create_a_workspace(self):
        for arguments in (
            [],
            ["run"],
            ["other", "/tmp/missing"],
            ["run", "/tmp/missing", "extra"],
        ):
            with self.assertRaisesRegex(ValueError, "exactly one"):
                PUBLIC.main(arguments)
