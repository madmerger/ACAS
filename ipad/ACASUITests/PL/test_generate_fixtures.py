import json
import tempfile
import unittest
from pathlib import Path

from generate_fixtures import fixture, seed_files


class EvidencePathTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve() / "evidence"
        self.run = self.root / "run"
        self.run.mkdir(parents=True)

    def test_report_sources_must_resolve_under_evidence_root(self):
        (self.run / "diff.json").write_text('{"changes": []}', encoding="utf-8")
        for kind in ["ledgers", "spool"]:
            path = self.run / "files" / kind / "report"
            path.parent.mkdir(parents=True)
            path.symlink_to(self.root.parent / "report")
            case = {"id": "PL-413", "legacy_result": {
                "evidence": ["run"],
                "comparison_targets": {
                    "keyed_record_diff": "run/diff.json",
                    "report_files": [str(path.relative_to(self.root))],
                },
            }}
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, "証跡ルート外"):
                fixture(self.root, case)

    def test_system_record_must_resolve_under_evidence_root(self):
        records = self.run / "before-records" / "records.json"
        records.parent.mkdir()
        records.write_text(json.dumps({"files": {str(self.root.parent / "system.dat"): {}}}), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "証跡ルート外"):
            seed_files(self.root, self.run)
