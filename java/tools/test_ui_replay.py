import unittest
from contextlib import redirect_stderr
from io import StringIO
from unittest.mock import patch

import ui_replay


class UiReplayTest(unittest.TestCase):
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
