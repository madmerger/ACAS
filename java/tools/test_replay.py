import unittest
from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch
from urllib.error import HTTPError
from urllib.request import HTTPCookieProcessor, HTTPHandler, ProxyHandler, build_opener
from urllib.response import addinfourl

import replay
import ui_replay
import calc_replay


class ReplayTest(unittest.TestCase):
    def test_terminal_text_escapes_nonprinting_characters(self):
        self.assertEqual(replay.terminal_text("確認\n" + chr(27)), r"確認\n\x1b")

    def test_calculator_requires_token_before_reading_catalog(self):
        with patch.dict("replay.os.environ", {}, clear=True), patch("sys.argv", ["calc_replay.py", "evidence"]), \
                patch("calc_replay.load_catalog") as catalog, patch("sys.stderr"):
            with self.assertRaises(SystemExit) as error:
                calc_replay.main()
            self.assertEqual(error.exception.code, 2)
            catalog.assert_not_called()

    def test_api_refuses_non_loopback_before_building_transport(self):
        for url in ["https://example.invalid", "http://192.0.2.1", "http://localhost.example.invalid"]:
            with self.subTest(url=url), patch("replay.urllib.request.build_opener") as build:
                with self.assertRaisesRegex(ValueError, "ループバック"):
                    replay.Api(url)
                build.assert_not_called()

    def test_api_builds_opener_without_proxies(self):
        with patch("replay.urllib.request.build_opener") as build:
            for host in ["127.0.0.1", "[::1]", "localhost"]:
                replay.Api(f"http://{host}:18080")
                proxy, redirect, cookies = build.call_args.args
                self.assertEqual(proxy.proxies, {})
                self.assertIsInstance(redirect, replay.NoRedirect)
                self.assertIsInstance(cookies, HTTPCookieProcessor)

    def test_api_sends_token_to_all_paths_and_does_not_follow_redirect(self):
        seen = []

        class SyntheticHttpHandler(HTTPHandler):
            def http_open(self, request):
                seen.append((request.selector, request.get_header("X-acas-test-token")))
                redirected = request.selector == "/api/redirect"
                headers = {"Location": "/not-requested"} if redirected else {}
                response = addinfourl(BytesIO(b""), headers, request.full_url, 302 if redirected else 200)
                response.msg = "synthetic response"
                return response

        api = replay.Api("http://localhost")
        api.opener = build_opener(ProxyHandler({}), replay.NoRedirect(), SyntheticHttpHandler())
        with patch.dict("replay.os.environ", {"ACAS_TEST_API_TOKEN": "synthetic"}):
            api.call("GET", "/api/test/snapshot")
            api.call("POST", "/api/sessions")
            with self.assertRaises(HTTPError) as error:
                api.call("GET", "/api/redirect")
        self.assertEqual(error.exception.code, 302)
        self.assertEqual(seen, [("/api/test/snapshot", "synthetic"), ("/api/sessions", "synthetic"),
                                ("/api/redirect", "synthetic")])

    def test_comparison_paths_cannot_leave_evidence_root(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            evid = root / "evidence"
            report_dir = evid / "files/ledgers"
            report_dir.mkdir(parents=True)
            outside = root / "sample.txt"
            outside.write_text("synthetic fixture")
            (report_dir / "sample.txt").symlink_to(outside)
            targets = {"screen_text": ["../sample.txt"], "keyed_record_diff": str(outside),
                       "report_files": ["files/ledgers/sample.txt"]}
            case = {"id": "GL-test", "title": "証跡", "baseline": "biz",
                    "runner": {"app": "gl", "steps": [{"key": "ENTER"}]},
                    "legacy_result": {"verdict": "合格", "comparison_targets": targets}}
            api = Mock(spec=replay.Api)
            api.call.side_effect = [None, {}, {"id": 1}, None, {"text": ""}, {"text": ""}, {}, None]
            with patch.object(Path, "read_text") as read_text, patch.object(Path, "read_bytes") as read_bytes:
                result = replay.run_case(api, evid, case)
            self.assertEqual(result["verdict"], "未検証")
            self.assertEqual(result["reason"].count("展開ルート内"), 3)
            read_text.assert_not_called()
            read_bytes.assert_not_called()

    def test_all_replay_entry_points_reject_outside_catalog(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            evid = root / "evidence"
            evid.mkdir()
            (root / "catalog.json").write_text('{"cases": []}')
            (evid / "scenarios").symlink_to(root, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "展開ルート内"):
                replay.main(args=replay.argument_parser().parse_args([str(evid), "GL-test"]))
            with self.assertRaisesRegex(ValueError, "展開ルート内"):
                ui_replay.main([str(evid), "CALC-"])
            with patch.dict("replay.os.environ", {"ACAS_TEST_API_TOKEN": "a" * 32}), \
                    patch("calc_replay.argparse.ArgumentParser.parse_args") as parse_args:
                parse_args.return_value.evidence = evid
                with self.assertRaisesRegex(ValueError, "展開ルート内"):
                    calc_replay.main()

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

    def test_observed_difference_takes_priority_over_missing_evidence(self):
        case = {"id": "GL-test", "title": "画面比較", "baseline": "biz",
                "runner": {"app": "gl", "steps": [{"key": "ENTER"}]},
                "legacy_result": {"verdict": "合格", "comparison_targets": {
                    "screen_text": ["screen.txt"], "keyed_record_diff": "missing.json"}}}
        api = Mock(spec=replay.Api)
        api.call.side_effect = [None, {}, {"id": 1}, None, {"text": "Web画面"}, {"text": ""}, {}, None]
        with TemporaryDirectory() as tmp:
            evid = Path(tmp)
            (evid / "screen.txt").write_text("レガシー画面")
            result = replay.run_case(api, evid, case)
        self.assertEqual(result["verdict"], "不一致")
        self.assertIn("画面相違", result["reason"])
        self.assertIn("レコード差分証跡なし", result["reason"])
