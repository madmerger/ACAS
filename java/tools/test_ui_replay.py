import unittest
from contextlib import redirect_stderr
from io import StringIO
from unittest.mock import patch

import ui_replay


class UiReplayTest(unittest.TestCase):
    def test_visible_calc_result_is_compared_independently_of_payload(self):
        for name, actual, shown, wrong in [
            ("vat", {"vat": "20.00"}, "税額：20.00", "税額：-20.00"),
            ("avg", {"cost": "33.3333"}, "平均原価：33.3333", "平均原価：33.3334"),
            ("avg", {"cost": None}, "数量が0のため、平均原価を計算できません。", "平均原価：0"),
            ("date", {"valid": True, "integer": 154557, "normalized": "29/02/2024"},
             "通算日：154557　日付：29/02/2024", "通算日：154557　日付：28/02/2024"),
            ("date", {"valid": False, "integer": 0, "normalized": None},
             "日付が無効です（通算日：0）。日／月／年の順に確認してください。",
             "日付が無効です（通算日：1）。日／月／年の順に確認してください。"),
        ]:
            with self.subTest(name=name, shown=shown):
                self.assertEqual(ui_replay.calc_verdict(name, actual, actual, shown)[0], "一致")
                verdict, reason = ui_replay.calc_verdict(name, actual, actual, wrong)
                self.assertEqual(verdict, "不一致")
                self.assertIn("画面表示", reason)
                self.assertEqual(ui_replay.calc_verdict(name, actual, actual, "通信エラー")[0], "未検証")
                self.assertEqual(ui_replay.calc_verdict(name, actual, {}, shown)[0], "未検証")

    def test_mixed_case_types_fail_before_dispatch(self):
        with patch("ui_replay.main_calc") as calc, patch("ui_replay.replay.main") as business:
            stderr = StringIO()
            with redirect_stderr(stderr), self.assertRaises(SystemExit) as error:
                ui_replay.main(["evidence", "CALC-", "GL-001"])
            self.assertEqual(error.exception.code, 2)
            self.assertIn("CALC と業務ケースは別々に指定", stderr.getvalue())
            calc.assert_not_called()
            business.assert_not_called()

    def test_case_types_use_only_positional_selectors(self):
        with patch("ui_replay.main_calc") as calc, patch("ui_replay.replay.main") as business:
            ui_replay.main(["evidence", "CALC-200"])
            self.assertEqual(calc.call_args.args[0].cases, ["CALC-200"])
            ui_replay.main(["CALC-evidence", "GL-001", "--out", "CALC-results.json"])
            self.assertEqual(business.call_args.args[1].cases, ["GL-001"])
