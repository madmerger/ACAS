import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock

import replay
import ui_replay


class ReplayTest(unittest.TestCase):
    def test_wrapped_nohup_notice_is_masked_before_screen_normalization(self):
        col = 79 - replay.OS_OUTPUT.index(" ")
        prefix = "L" * col
        def wrap(text):
            return text[:80] + "\n" + text[80:] + "\n"

        case = {"id": "GL-test", "title": "画面比較", "baseline": "biz",
                "runner": {"app": "gl", "steps": [{"key": "ENTER"}]},
                "legacy_result": {"verdict": "合格", "comparison_targets": {"screen_text": ["screen.txt"]}}}
        with TemporaryDirectory() as tmp:
            evid = Path(tmp)
            (evid / "screen.txt").write_text(wrap(prefix + replay.OS_OUTPUT + "right"))
            for suffix, verdict in [("right", "一致"), ("wrong", "不一致")]:
                with self.subTest(suffix=suffix):
                    screen = wrap(prefix + "X" * len(replay.OS_OUTPUT) + suffix)
                    api = Mock(spec=replay.Api)
                    api.call.side_effect = [None, {}, {"id": 1}, None, {"text": screen}, {"text": ""}, {}, None]
                    result = replay.run_case(api, evid, case)
                    self.assertEqual(result["verdict"], verdict)
                    self.assertIn("OS 出力行は比較対象外: 1 箇所", result["reason"])

    def test_nohup_mask_preserves_application_text(self):
        for notice, col in [(replay.OS_OUTPUT, 2), (replay.OS_OUTPUT, 73), (replay.OS_ERROR, 1)]:
            with self.subTest(notice=notice, col=col):
                text = "L" * col + notice + "right"
                other = "L" * col + "X" * len(notice) + "WRONG"
                split = lambda s: [s[i:i + 80] for i in range(0, len(s), 80)]
                want, got, count = replay.mask_os_output(split(text), split(other))
                self.assertEqual(count, 1)
                self.assertTrue(want[-1].endswith("right"))
                self.assertTrue(got[-1].endswith("WRONG"))
                self.assertEqual(want[0][:col], got[0][:col])
                self.assertNotEqual(want, got)

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
