import unittest
from pathlib import Path
from unittest.mock import Mock

import replay
import ui_replay


class ReplayTest(unittest.TestCase):
    def test_browser_does_not_silently_drop_irs_path(self):
        case = {
            "id": "INT-test", "title": "IRS ディレクトリ選択", "baseline": "biz",
            "runner": {"app": "irs", "irs_path": "ledgers/acas", "steps": [{"key": "ENTER"}]},
            "legacy_result": {"verdict": "合格"},
        }
        api = ui_replay.UiApi.__new__(ui_replay.UiApi)
        api.call = Mock()
        got = replay.run_case(api, Path("."), case)
        self.assertEqual(got["verdict"], "未検証")
        self.assertIn("IRS", got["reason"])
        api.call.assert_not_called()
