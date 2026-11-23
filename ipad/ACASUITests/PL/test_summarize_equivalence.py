import json
import tempfile
import unittest
from pathlib import Path

from summarize_equivalence import compare_attempt, comparison_note, csv_cell, observed_summary, original_reports, read_run


class RunHistoryTests(unittest.TestCase):
    def test_csv_cells_escape_formula_prefixes(self):
        for cell in ("=文字列", "+1", "-1", "@例", "\t =例"):
            self.assertEqual(csv_cell(cell), "'" + cell)
        self.assertEqual(csv_cell("原本と一致"), "原本と一致")

    def test_report_source_must_stay_in_evidence_root(self):
        case = {"id": "PL-222", "legacy_result": {"comparison_targets": {
            "report_files": ["../files/ledgers/report"],
        }}}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, "証跡ルート外"):
                original_reports(case, root, root, "一致")

    def test_distinguishes_ui_failure_from_byte_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            (run / "recording.json").write_text(json.dumps({"startEpoch": 100}))
            (run / "xcodebuild.log").write_text(
                "Test Case '-[ACASUITests.PurchaseFlows testPL090]' started.\n"
                "ACAS_PL_START|PL-090|113.5\n"
                "PurchaseFlows.swift:4: error: -[ACASUITests.PurchaseFlows testPL090] : 入力画面で停止\n"
                "Test Case '-[ACASUITests.PurchaseFlows testPL090]' failed (23.00 seconds).\n"
                "Test Case '-[ACASUITests.PurchaseFlows testPL222]' started.\n"
                "ACAS_PL_START|PL-222|140.5\n"
                "ACAS_PL_RESULT|PL-222|case.verdict.mismatch|prt-1: 期待 200 B / 実測 10\n"
                "PurchaseFlows.swift:4: error: -[ACASUITests.PurchaseFlows testPL222] : "
                "XCTAssertNotEqual failed: case.verdict.mismatch — 帳票差分\n"
                "Test Case '-[ACASUITests.PurchaseFlows testPL222]' failed (23.00 seconds).\n"
            )
            results = read_run(run)
            self.assertEqual(results["PL-090"]["start"], 13.5)
            self.assertEqual(results["PL-090"]["verdict"], "未判定")
            self.assertIn("入力画面で停止", results["PL-090"]["reason"])
            self.assertEqual(results["PL-222"]["verdict"], "不一致")
            self.assertEqual(results["PL-222"]["reason"], "prt-1: 期待 200 B / 実測 10")
            self.assertEqual(comparison_note(results["PL-222"]["reason"]), "prt-1：原本 200 B、実測 10 B")

    def test_report_summary_uses_observed_bytes_and_original_size(self):
        case = {"id": "PL-222", "legacy_result": {"comparison_targets": {
            "report_files": ["runs/sample/files/ledgers/acas/prt-1"],
        }}}
        result = {"verdict": "不一致", "reason": "ledgers/acas/prt-1: 期待 1200 B / 実測 3"}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = root / case["legacy_result"]["comparison_targets"]["report_files"][0]
            expected.parent.mkdir(parents=True)
            expected.write_bytes(b"a" * 1200)
            actual = root / "actual" / "PL-222" / "prt-1"
            actual.parent.mkdir(parents=True)
            actual.write_bytes(b"abc")
            reports = original_reports(case, root, root / "actual", result["verdict"])
        self.assertEqual(observed_summary(case, result, reports), "帳票 3 B を生成、原本 1,200 B")
        self.assertIn("最初の差分位置 1", reports[0][1])

    def test_direct_difference_applies_only_to_its_attempt(self):
        target = "run/files/ledgers/acas/prt-1"
        case = {"id": "PL-018", "legacy_result": {"comparison_targets": {"report_files": [target]}}}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = root / target
            expected.parent.mkdir(parents=True)
            expected.write_bytes(b"a")
            for name, report, verdict in (
                    ("first", b"b", "不一致"), ("last", b"a", "一致"), ("missing", None, "一致")):
                run = root / name
                if report is not None:
                    actual = run / "reports/PL-018/prt-1"
                    actual.parent.mkdir(parents=True)
                    actual.write_bytes(report)
                result, reports = compare_attempt(case, root, {"run": run, "verdict": "一致", "reason": ""})
                self.assertEqual(result["verdict"], verdict)
                self.assertEqual(bool(result["reason"]), verdict == "不一致")
                if report is None:
                    self.assertIn("直接照合用の出力なし", reports[0][1])
            attempt = {"run": root / "first", "verdict": "一致", "reason": "条件画面到達：帳票未作成"}
            result, reports = compare_attempt(case, root, attempt)
            self.assertEqual(observed_summary(case, result, reports), "帳票 1 B を生成、原本 1 B")

    def test_summary_distinguishes_screen_reached_from_legacy_not_executed(self):
        case = {"id": "PL-003", "title": "Purchase Ledger Enquiry — 画面表示"}
        result = {"verdict": "対象外", "reason": "到達先ヘッダに無い: PL015"}
        self.assertEqual(observed_summary(case, result, []), "PL015 画面に到達、旧証跡では未実施")
