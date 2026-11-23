import json
import re
import tempfile
import unittest
from pathlib import Path

from generate_fixtures import (
    CASE_NAMES, check_required_cases, equivalence_fixture, fixture, purchase_case_ids, seed_files, validate_case_id,
)


class EvidencePathTests(unittest.TestCase):
    def test_each_purchase_case_has_a_japanese_display_name(self):
        self.assertEqual(CASE_NAMES.keys(), purchase_case_ids())
        self.assertTrue(all(re.search(r"[ぁ-んァ-ヶ一-龯]", name) for name in CASE_NAMES.values()))
        self.assertEqual(CASE_NAMES["PL-007"], "仕入の検証帳票 — 画面表示")

    def test_incomplete_catalog_removes_stale_purchase_outputs(self):
        fixtures = self.root / "fixtures"
        fixtures.mkdir()
        for name in ("PL-413.json", "PL-001.json", "SL-001.json"):
            (fixtures / name).touch()
        cases = dict.fromkeys(purchase_case_ids() - {"PL-413"})
        with self.assertRaisesRegex(ValueError, "PL-413"):
            check_required_cases(cases, fixtures)
        self.assertEqual([path.name for path in fixtures.iterdir()], ["SL-001.json"])

    def test_case_id_requires_three_ascii_digits(self):
        self.assertEqual(validate_case_id("PL-001"), "PL-001")
        for case_id in ("PL-01", "PL-００１", "PL-001/extra"):
            with self.subTest(case_id=case_id), self.assertRaises(ValueError):
                validate_case_id(case_id)

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

    def test_only_unexecuted_cases_are_out_of_scope(self):
        (self.run / "diff.json").write_text('{"changes": []}', encoding="utf-8")
        records = self.run / "before-records"
        records.mkdir()
        (records / "records.json").write_text('{"files": {}}', encoding="utf-8")
        (self.run / "terminal.cast").write_text('{"timestamp": 0}\n', encoding="utf-8")
        (self.run / "screen.txt").write_text(
            "Purchase Ledger System Menu\nT-025 Error not in error.txt.", encoding="utf-8")
        legacy = {"evidence": ["run"], "verdict": "相違", "reason": "到達先ヘッダに無い",
                  "comparison_targets": {"keyed_record_diff": "run/diff.json", "report_files": [],
                                         "screen_text": ["run/screen.txt"]}}
        case = {"id": "PL-003", "title": "買掛残高・明細照会", "legacy_result": legacy}
        generated = equivalence_fixture(self.root, case)
        self.assertEqual(generated["title"], CASE_NAMES["PL-003"])
        comparison = generated["equivalence"]
        self.assertIsNone(comparison["outOfScope"])
        self.assertEqual(comparison["checkpoint"]["kind"], "blocked")
        self.assertIn("T-025", comparison["checkpoint"]["detail"])
        legacy.update(verdict="未実施", reason="実行せず")
        comparison = equivalence_fixture(self.root, case)["equivalence"]
        self.assertEqual(comparison["outOfScope"], "実行せず")
        self.assertIsNone(comparison["checkpoint"])
