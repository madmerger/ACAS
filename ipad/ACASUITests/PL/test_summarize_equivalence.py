import csv
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from summarize_equivalence import (
    compare_attempt, comparison_note, csv_cell, main, markdown_text, observed_summary, original_reports, read_run,
    video_start,
)


class RunHistoryTests(unittest.TestCase):
    @unittest.skipUnless(importlib.util.find_spec("openpyxl"), "Excel 出力の検証には openpyxl が必要")
    def test_excel_video_offsets_are_numeric_and_csv_offsets_keep_two_decimals(self):
        from openpyxl import load_workbook

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            offsets = {"PL-003": 100.25, "PL-006": 20.5, "PL-007": 0.0}
            cases = [{"id": case, "legacy_result": {"comparison_targets": {"report_files": []}}}
                     for case in (*offsets, "PL-008")]
            catalog = root / "scenarios/catalog.json"
            catalog.parent.mkdir()
            catalog.write_text(json.dumps({"cases": cases}))
            (root / "recording.json").write_text(json.dumps({"startEpoch": 0}))
            (root / "xcodebuild.log").write_text("".join(
                f"Test Case '-[ACASUITests.PurchaseFlows testPL{case[3:]}]' started.\n"
                f"ACAS_PL_RESULT|{case}|case.verdict.match|\n"
                f"Test Case '-[ACASUITests.PurchaseFlows testPL{case[3:]}]' passed\n"
                for case in offsets))
            timeline = root / "timeline.json"
            timeline.write_text(json.dumps([{"run": directory, "offset": 0, "caseStarts": offsets}]))
            with patch("sys.argv", ["summarize_equivalence.py", directory, directory, str(timeline), "--xlsx"]):
                main()
            with (root / "ACAS-PL.csv").open(encoding="utf-8-sig", newline="") as handle:
                self.assertEqual([row["動画開始時刻(秒)"] for row in csv.DictReader(handle)],
                                 ["100.25", "20.50", "0.00", ""])
            workbook = load_workbook(root / "ACAS-PL.xlsx")
            try:
                cells = workbook.active["F"][1:]
                self.assertEqual([cell.value for cell in cells], [100.25, 20.5, 0, None])
                self.assertEqual([cell.data_type for cell in cells[:3]], ["n"] * 3)
                self.assertEqual([cell.number_format for cell in cells[:3]], ["0.00"] * 3)
            finally:
                workbook.close()

    def test_verified_frame_offset_takes_precedence_over_log_clock(self):
        part = {"offset": 30.0, "trim": 5.0, "caseStarts": {"PL-003": 0.0}}
        self.assertEqual(video_start(part, "PL-003", 8.0), 30.0)
        self.assertEqual(video_start(part, "PL-006", 22.0), 47.0)
        self.assertIsNone(video_start(part, "PL-007", None))

    def test_markdown_evidence_is_rendered_as_literal_inline_text(self):
        self.assertEqual(
            markdown_text("![記録](画像)\n# <記録> & `原本` **確認**"),
            r"\!\[記録\]\(画像\) \# \<記録\> \& \`原本\` \*\*確認\*\*",
        )

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
        self.assertIn("先頭 1 B 一致、2 バイト目が最初の差分（原本 61、移行版 62）", reports[0][1])

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

    def test_summary_reports_observed_rejection_instead_of_screen_arrival(self):
        result = {"verdict": "一致", "reason": "旧版は T-025 で拒否、対象画面には進まない、"
                  "移行版の警告：T-025： 仕入取引が転記されていません。"}
        self.assertEqual(observed_summary({"id": "PL-003"}, result, []),
                         "T-025： 仕入取引が転記されていません。 対象画面へ進まず、保存差分なし")
