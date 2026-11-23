import tempfile
import unittest
from pathlib import Path

from generate_cases import evidence_path, expected_changes, fixture, save, snapshot_seed


class EvidencePathTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve() / "evidence"
        self.root.mkdir()
        self.outside = self.root.with_name("evidence-other")
        self.outside.mkdir()

    def test_resolved_paths_must_stay_under_evidence_root(self):
        (self.root / "inside").mkdir()
        (self.root / "alias").symlink_to("inside", target_is_directory=True)
        self.assertEqual(evidence_path(self.root, "alias/data.json"), self.root / "inside/data.json")
        for path in [self.outside / "data.json", "../evidence-other/data.json"]:
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "証跡ルート外"):
                evidence_path(self.root, path)

    def test_report_and_spool_reject_external_symlinks(self):
        for directory in ["ledgers", "spool"]:
            path = Path("run/files") / directory / "report"
            (self.root / path).parent.mkdir(parents=True)
            (self.root / path).symlink_to(self.outside / "report")
            case = {"id": "SL-104", "legacy_result": {
                "evidence": ["run"],
                "comparison_targets": {"report_files": [path.as_posix()]},
            }}
            with self.subTest(directory=directory), self.assertRaisesRegex(ValueError, "証跡ルート外"):
                fixture(self.root, case)

    def test_diff_and_snapshot_reject_external_files(self):
        run = self.root / "run"
        (run / "before-records").mkdir(parents=True)
        save(run / "before-records/records.json", {"files": {str(self.outside / "system.dat"): {}}})
        with self.assertRaisesRegex(ValueError, "証跡ルート外"):
            snapshot_seed(self.root, run)
        with self.assertRaisesRegex(ValueError, "証跡ルート外"):
            expected_changes(self.root, self.outside / "changes.json")

    def test_batch_diff_uses_the_six_byte_index_key(self):
        change = {
            "file": "ledgers/acas/batch.dat", "key": "999999", "before": None,
            "after": {"hex": b"999999000099".hex()},
        }
        save(self.root / "changes.json", {"changes": [change]})
        self.assertEqual(expected_changes(self.root, "changes.json"), [{
            "file": change["file"], "key": b"999999".hex(),
            "before": None, "after": change["after"]["hex"],
        }])


if __name__ == "__main__":
    unittest.main()
