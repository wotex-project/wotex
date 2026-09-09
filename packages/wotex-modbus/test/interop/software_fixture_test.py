"""Failure-boundary tests for the software runner; protocol evidence comes from ExUnit."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import software_fixture as fixture


class FixtureRunnerTest(unittest.TestCase):
    def test_archive_source_identity_does_not_require_git_or_trust_a_head_label(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "lib").mkdir()
            source = root / "lib/example.ex"
            source.write_text("first version")
            first = fixture.source_identity(root)
            self.assertIsNone(first["commit"])
            self.assertEqual(first["source_files_sha256"], {"lib/example.ex": fixture.digest(source)})
            source.write_text("second version")
            self.assertNotEqual(first["source_sha256"], fixture.source_identity(root)["source_sha256"])

    def test_unrelated_workspace_is_refused_without_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sentinel = root / "retain"
            sentinel.write_text("caller-owned")
            with self.assertRaisesRegex(ValueError, "unrelated nonempty"):
                fixture.build(root)
            self.assertEqual(list(root.iterdir()), [sentinel])
            self.assertEqual(sentinel.read_text(), "caller-owned")

    def test_corrupt_source_is_rejected_before_any_image_operation(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(fixture, "capture") as capture:
            root = Path(temporary)
            (root / "source.tar.gz").write_bytes(b"corrupted")
            manifest = {"format": fixture.FORMAT, "source_commit": fixture.PIN,
                        "inputs": fixture.subject()["inputs"]}
            with self.assertRaisesRegex(ValueError, "archive hash mismatch"):
                fixture.verify(root, manifest)
            capture.assert_not_called()

    def test_cleanup_removes_only_the_owned_container_even_when_stop_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            calls = []

            def command(argv, **_options):
                calls.append(argv)
                if argv[1] == "stop":
                    raise RuntimeError("stop failure")

            evidence = {"status": "passed"}
            with patch.object(fixture, "run", command), patch.object(fixture, "capture", return_value=""):
                fixture.cleanup_peer("owned-id", Path(temporary), evidence)
            self.assertEqual(calls[-1], ["docker", "rm", "--force", "owned-id"])
            self.assertEqual(evidence["status"], "failed")
            self.assertEqual(evidence["owned_containers_after"], 0)
            self.assertIn("stop failure", evidence["cleanup_errors"][0])

    def test_cleanup_failure_never_claims_zero_owned_resources(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = {"status": "passed"}
            with patch.object(fixture, "run", side_effect=RuntimeError("daemon unavailable")):
                fixture.cleanup_peer("owned-id", Path(temporary), evidence)
            self.assertEqual(evidence["status"], "failed")
            self.assertNotIn("owned_containers_after", evidence)
            self.assertEqual(len(evidence["cleanup_errors"]), 2)

    def test_missing_tools_fail_before_workspace_lock_or_resource_creation(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary) / "peer"
            with patch.object(fixture.sys, "argv", ["software_fixture.py", "run", str(workspace)]), \
                    patch.object(fixture.shutil, "which", return_value=None):
                with self.assertRaisesRegex(RuntimeError, "required software tool missing"):
                    fixture.main()
            self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_result_file_write_is_complete_json(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "result.json"
            fixture.write_json(path, {"status": "failed", "failure": "fixture unavailable"})
            self.assertEqual(json.loads(path.read_text())["status"], "failed")
            self.assertEqual(list(Path(temporary).iterdir()), [path])


if __name__ == "__main__":
    unittest.main()
