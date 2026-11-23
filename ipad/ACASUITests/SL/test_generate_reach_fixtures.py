import hashlib
import tempfile
import unittest
from pathlib import Path

from generate_reach_fixtures import BASE, report_evidence


class UnchangedReportsTests(unittest.TestCase):
    def test_only_documented_unchanged_report_bytes_are_compared(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory).resolve()
            run = evidence / "run"
            path = "ledgers/acas/prt-1"
            source = run / "before-files" / path
            source.parent.mkdir(parents=True)
            source.write_bytes(b"original")
            metadata = {"size": 8, "sha256": hashlib.sha256(b"original").hexdigest()}
            before = {path: metadata, "ledgers/acas/prt-2": metadata}
            BASE.save(run / "before.json", before)
            BASE.save(run / "result.json", {"after": before})
            self.assertEqual(report_evidence(evidence, run, []), ({path: b"original".hex()}, {path: b"original".hex()}))

            source.write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "帳票の証跡バイトが一致しません"):
                report_evidence(evidence, run, [])

            BASE.save(run / "result.json", {"after": {"ledgers/acas/prt-2": metadata}})
            with self.assertRaisesRegex(ValueError, "到達確認の帳票が変化しました"):
                report_evidence(evidence, run, [])

    def test_new_empty_report_is_expected_but_not_seeded(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory).resolve()
            run = evidence / "run"
            path = "ledgers/acas/prt-3"
            output = run / "files" / path
            output.parent.mkdir(parents=True)
            output.write_bytes(b"")
            BASE.save(run / "before.json", {})
            BASE.save(run / "result.json", {"after": {path: {"sha256": hashlib.sha256(b"").hexdigest()}}})
            self.assertEqual(report_evidence(evidence, run, [output]), ({}, {path: ""}))


if __name__ == "__main__":
    unittest.main()
