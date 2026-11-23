import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock

import replay
import ui_replay


class ReplayTest(unittest.TestCase):
    def test_missing_evidence_is_unverified(self):
        case = {
            "id": "GL-test", "title": "比較証跡", "baseline": "biz",
            "runner": {"app": "gl", "steps": [{"key": "ENTER"}]},
            "legacy_result": {"verdict": "合格"},
        }
        with TemporaryDirectory() as tmp:
            evid = Path(tmp)
            (evid / "screen.txt").write_text("同じ画面", encoding="utf-8")
            for targets, verdict, reason in [
                ({}, "未検証", "比較対象なし"),
                ({"screen_text": ["missing.txt"]}, "未検証", "画面証跡なし"),
                ({"screen_text": ["screen.txt", "extra.txt"]}, "未検証", "対応する操作手順なし"),
                ({"screen_text": ["screen.txt"], "keyed_record_diff": "missing.json"}, "未検証", "レコード差分証跡なし"),
                ({"screen_text": ["screen.txt"], "report_files": ["files/ledgers/acas/prt-1"]}, "未検証", "帳票証跡"),
                ({"screen_text": ["screen.txt"]}, "一致", "レガシー実測と一致"),
            ]:
                with self.subTest(targets=targets):
                    case["legacy_result"]["comparison_targets"] = targets
                    api = Mock(spec=replay.Api)
                    api.supports_irs_path = True
                    api.call.side_effect = [None, {}, {"id": 1}, None, {"text": "同じ画面"}, {"text": ""}, {}, None]
                    result = replay.run_case(api, evid, case)
                    self.assertEqual(result["verdict"], verdict)
                    self.assertIn(reason, result["reason"])

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
