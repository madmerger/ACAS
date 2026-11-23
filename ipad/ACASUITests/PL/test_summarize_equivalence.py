import json
import tempfile
import unittest
from pathlib import Path

from summarize_equivalence import read_run


class RunHistoryTests(unittest.TestCase):
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
                "Test Case '-[ACASUITests.PurchaseFlows testPL222]' failed (23.00 seconds).\n"
            )
            results = read_run(run)
            self.assertEqual(results["PL-090"]["start"], 13.5)
            self.assertEqual(results["PL-090"]["verdict"], "未判定")
            self.assertIn("入力画面で停止", results["PL-090"]["reason"])
            self.assertEqual(results["PL-222"]["verdict"], "不一致")
            self.assertEqual(results["PL-222"]["reason"], "prt-1: 期待 200 B / 実測 10")
